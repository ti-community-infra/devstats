package main

import (
	"encoding/json"
	"fmt"
	"strings"

	"github.com/emirpasic/gods/stacks/linkedliststack"
	"github.com/go-git/go-git/v5"
	"github.com/go-git/go-git/v5/plumbing/object"
	"github.com/go-git/go-git/v5/storage/memory"
	"github.com/google/uuid"
	"github.com/sirupsen/logrus"
	"github.com/ti-community-infra/devstats/internal/pkg/identifier"
	"github.com/ti-community-infra/devstats/internal/pkg/lib"
	"github.com/ti-community-infra/devstats/internal/pkg/storage/model"
	"gorm.io/gorm"
	"gorm.io/gorm/clause"
)

const DefaultTeamsFolderPath = "teams"
const DefaultMembershipFileName = "membership.json"

type ProjectConfig struct {
	Name             string
	DisplayName      string
	DefaultOrgName   string
	CommunityRepoURL string

	// UseTeamJSON means this project use json format to store community teams information.
	UseTeamJSON        bool
	TeamsFolderPath    string
	MembershipFileName string
	StartCommitSHA     string
}

type TeamMembership struct {
	Name         string   `json:"name,omitempty"`
	Description  string   `json:"description,omitempty"`
	Maintainers  []string `json:"maintainers"`
	Committers   []string `json:"committers"`
	Reviewers    []string `json:"reviewers"`
	Repositories []string `json:"repositories,omitempty"`
}

func main() {
	var ctx identifier.Ctx
	err := ctx.Init()
	lib.FatalOnError(err)

	// Init logger.
	log := logrus.WithField("program", "sync_teams")

	// Init database client.
	conn, err := lib.NewConn(ctx.IDDbDialect, ctx.IDDbHost, ctx.IDDbPort, ctx.IDDbUser, ctx.IDDbPass, ctx.IDDbName)
	lib.FatalOnError(err)

	// Init GitHub Client.
	gc := identifier.GitHubClient{}
	err = gc.Init(&ctx, log, nil)
	if err != nil {
		lib.FatalOnError(err)
		return
	}

	// Make sure the table structure is existed.
	identifier.EnsureStructure(log, conn)

	// ProjectConfig Config.
	projects := []ProjectConfig{
		{
			DisplayName:        "TiDB",
			Name:               "tidb",
			DefaultOrgName:     "pingcap",
			CommunityRepoURL:   "https://github.com/pingcap/community",
			TeamsFolderPath:    DefaultTeamsFolderPath,
			MembershipFileName: DefaultMembershipFileName,
			StartCommitSHA:     "fe66c24508d4fecbee903d7a78df2f16cdfbb13b",
			UseTeamJSON:        true,
		},
		{
			DisplayName:        "TiKV",
			Name:               "tikv",
			DefaultOrgName:     "tikv",
			CommunityRepoURL:   "https://github.com/tikv/community",
			TeamsFolderPath:    DefaultTeamsFolderPath,
			MembershipFileName: "team.json",
			StartCommitSHA:     "e7679a47047c1f042abf4e53c112e564bd5008ee",
			UseTeamJSON:        true,
		},
	}

	for _, projectConfig := range projects {
		if projectConfig.UseTeamJSON {
			getCommunityInfoByTeams(conn, &gc, projectConfig)
		}
	}
}

func getCommunityInfoByTeams(db *gorm.DB, gc *identifier.GitHubClient, projectConfig ProjectConfig) {
	logrus.Infof("Cloning the repository: %s", projectConfig.CommunityRepoURL)
	r, err := git.Clone(memory.NewStorage(), nil, &git.CloneOptions{
		URL:               projectConfig.CommunityRepoURL,
		RecurseSubmodules: git.DefaultSubmoduleRecursionDepth,
	})
	lib.FatalOnError(err)

	// Ensure the project existed in the database.
	var project model.Project
	project.Name = projectConfig.Name
	project.DisplayName = projectConfig.DisplayName
	err = db.Where("name = ?", projectConfig.Name).FirstOrCreate(&project).Error
	lib.FatalOnError(err)

	// Get commits related to the teams directory.
	gitLog, err := r.Log(&git.LogOptions{
		Order: git.LogOrderCommitterTime,
		PathFilter: func(p string) bool {
			return strings.HasPrefix(p, projectConfig.TeamsFolderPath)
		},
	})
	lib.FatalOnError(err)

	// Sort by commit date in ascending order.
	commitStack := linkedliststack.New()
	err = gitLog.ForEach(func(commit *object.Commit) error {
		commitStack.Push(commit)
		return nil
	})
	lib.FatalOnError(err)

	nCommit := commitStack.Size()
	logrus.Infof("Found %d commits.", nCommit)

	// Traverse all commits to get the historical data of the membership file.
	for i := 0; i < nCommit; i++ {
		item, _ := commitStack.Pop()
		if item == nil {
			logrus.Warnf("Got nil commit.")
			continue
		}
		commit := item.(*object.Commit)
		logrus.Infof("Handling commit %s <%s, %s>", commit.Hash, commit.Committer.Name, commit.Committer.When)

		// Switch to the teams directory.
		tree, err := commit.Tree()
		lib.FatalOnError(err)
		teamsPath := projectConfig.TeamsFolderPath
		tree, err = tree.Tree(teamsPath)
		if err != nil {
			logrus.WithError(err).Errorf("Failed to found directory: %s", teamsPath)
		}
		lib.FatalOnError(err)

		// Traverse all the team folders.
		teamNames := make(lib.StringSet)
		for _, entry := range tree.Entries {
			if entry.Mode.IsFile() {
				continue
			}

			teamName := entry.Name
			teamNames[teamName] = struct{}{}
			teamTree, err := tree.Tree(teamName)
			lib.FatalOnError(err)

			// Ensure team existed in the database.
			var team model.Team
			team.Name = teamName
			team.ProjectID = project.ID
			db.Where("project_id = ? and name = ?", project.ID, teamName).FirstOrCreate(&team)

			files := teamTree.Files()
			err = files.ForEach(func(file *object.File) error {
				if file.Name == projectConfig.MembershipFileName {
					contents, err := file.Contents()
					if err != nil {
						return err
					}

					var teamMembership TeamMembership
					err = json.Unmarshal([]byte(contents), &teamMembership)
					if err != nil {
						return err
					}

					team.Description = teamMembership.Description
					db.Updates(&team)

					saveTeamMembersToDB(db, gc, team.ID, team.Name, teamMembership, commit)

					repositories := teamMembership.Repositories
					if len(repositories) != 0 {
						saveTeamRepositoryToDB(db, gc, project.ID, team, projectConfig.DefaultOrgName, repositories)
					}
				}
				return nil
			})
			lib.FatalOnError(err)
		}

		// Handle the deleted teams.
		teamsInDB := make([]model.Team, 0)
		db.Where("project_id = ? and updated_at < ?", project.ID, commit.Committer.When).Find(&teamsInDB)
		teamNamesInDB := make(lib.StringSet)
		for _, team := range teamsInDB {
			teamNamesInDB[team.Name] = struct{}{}
		}

		// Exclude the teams existed in current commit, and the rest is the team that has been deleted.
		for teamName := range teamNames {
			delete(teamNamesInDB, teamName)
		}

		for teamDeletedName := range teamNamesInDB {
			db.Where("name = ? and project_id = ?", teamDeletedName, project.ID).Delete(&model.Team{})
			logrus.Infof("team %s has been deleted.", teamDeletedName)
		}
	}
}

func saveTeamMembersToDB(
	db *gorm.DB, gc *identifier.GitHubClient,
	teamID uint, teamName string, teamMembership TeamMembership, commit *object.Commit,
) {
	member2level := make(map[string]model.TeamLevel)

	for _, reviewer := range teamMembership.Reviewers {
		member2level[reviewer] = model.TeamReviewer
	}
	for _, committer := range teamMembership.Committers {
		member2level[committer] = model.TeamCommitter
	}
	for _, maintainer := range teamMembership.Maintainers {
		member2level[maintainer] = model.TeamMaintainer
	}

	for login, newLevel := range member2level {
		var githubUser model.GitHubUser
		db.Raw(`
select * from github_users u where exists(
    select * from github_user_logins ul where u.id = ul.github_user_id and ul.login = ?
)
`, login).Scan(&githubUser)

		if githubUser.ID == 0 {
			githubUserData, _, err := gc.GetUserByLogin(login)
			if err != nil {
				lib.FatalOnError(err)
				return
			}

			// Ensure unique identity existed in the database.
			var uniqueIdentity model.UniqueIdentity
			uniqueIdentity.UUID = uuid.NewString()
			err = db.Create(&uniqueIdentity).Error
			lib.FatalOnError(err)

			// Ensure GitHub user existed in the database.
			var newGitHubUser model.GitHubUser
			githubUserID := githubUserData.GetID()
			githubUserLogin := githubUserData.GetLogin()
			githubUserName := githubUserData.GetName()
			githubUserEmail := githubUserData.GetEmail()

			if login != githubUserLogin {
				logrus.Warnf("The team member github login have changed, before: %s now: %s", login, githubUserLogin)
			}

			newGitHubUser.ID = uint(githubUserID)
			newGitHubUser.Login = githubUserLogin
			newGitHubUser.Name = &githubUserName
			newGitHubUser.Email = githubUserEmail
			newGitHubUser.UUID = uniqueIdentity.UUID

			err = db.Where("id = ?", githubUserID).FirstOrCreate(&newGitHubUser).Error
			lib.FatalOnError(err)
			githubUser = newGitHubUser
		}

		// Find existed team member.
		var teamMember model.TeamMember
		db.Where("team_id = ? and uuid = ?", teamID, githubUser.UUID).First(&teamMember)
		oldLevel := teamMember.Level

		// Skip not level change member.
		if newLevel == oldLevel {
			continue
		}

		teamMember.TeamID = teamID
		teamMember.UUID = githubUser.UUID
		teamMember.DupGitHubID = githubUser.ID
		teamMember.DupGitHubLogin = login
		teamMember.DupEmail = githubUser.Email
		teamMember.Level = newLevel
		teamMember.LastUpdateDate = commit.Committer.When

		if len(oldLevel) == 0 {
			teamMember.JoinDate = commit.Committer.When
			logrus.Infof(
				"[Joinning] %s joined %s team as %s on %s.",
				login, teamName, newLevel, teamMember.JoinDate.Format("2006-01-02"),
			)
		} else if len(newLevel) != 0 {
			logrus.Infof(
				"[Promoation] %s is promoated from %s to %s in %s team on %s.",
				login, teamName, oldLevel, newLevel, teamMember.JoinDate.Format("2006-01-02"),
			)
		} else if len(newLevel) == 0 {
			logrus.Infof(
				"[Retirement] %s retired from the %s team on %s.",
				login, teamName, teamMember.JoinDate.Format("2006-01-02"),
			)
		}

		// Add team member relationship.
		db.Clauses(clause.OnConflict{
			Columns: []clause.Column{
				{Name: "team_id"}, {Name: "uuid"},
			},
			DoUpdates: clause.AssignmentColumns([]string{
				"dup_github_id", "dup_github_login", "level", "last_update_date",
			}),
		}).Create(&teamMember)

		// Add team member changelog.
		changeLog := model.TeamMemberChangeLog{
			TeamID:         teamID,
			UUID:           githubUser.UUID,
			CommitSHA:      commit.Hash.String(),
			CommitMessage:  commit.Message,
			ChangedAt:      commit.Committer.When,
			LevelFrom:      &oldLevel,
			LevelTo:        &newLevel,
			DupGitHubID:    githubUser.ID,
			DupGitHubLogin: login,
		}
		db.Clauses(clause.OnConflict{
			Columns: []clause.Column{
				{Name: "team_id"}, {Name: "uuid"}, {Name: "commit_sha"},
			},
			DoNothing: true,
		}).Create(&changeLog)
	}
}

func saveTeamRepositoryToDB(
	db *gorm.DB, gc *identifier.GitHubClient, projectID uint, team model.Team,
	defaultOrgName string, repositoryNames []string,
) {
	logrus.Infof("Found %d repositoies in %s team.", len(repositoryNames), team.Name)
	for _, repoName := range repositoryNames {
		var repository model.Repository
		owner := ""
		repo := ""

		// Process repo name.
		if strings.Contains(repoName, "/") {
			// If the name of the repo is complete, get org name by splitting.
			ary := strings.Split(repoName, "/")
			if len(ary) != 2 {
				logrus.Warnf("Skiping the wrong repo name: %s", repoName)
				continue
			}
			owner = ary[0]
			repo = ary[1]
			repository.Name = repoName
		} else {
			// If there is no owner part in repo name, use the default org name.
			owner = defaultOrgName
			repo = repoName
			repository.Name = fmt.Sprintf("%s/%s", defaultOrgName, repoName)
		}

		db.Where("name = ?", repository.Name).Find(&repository)

		// Get repository ID.
		if repository.ID == 0 {
			repositoryData, _, err := gc.GetRepository(owner, repo)
			if err != nil {
				logrus.WithError(err).Errorf("Failed to get repository id.")
				continue
			}

			repoID := repositoryData.GetID()
			repository.ID = uint(repoID)
		}

		repository.Owner = owner
		repository.ProjectID = projectID

		// Ensure the repository in the database.
		db.Clauses(clause.OnConflict{
			Columns: []clause.Column{
				{ Name: "id" },
			},
			DoNothing: true,
		}).Create(&repository)

		// Add repository for team.
		err := db.Model(&team).Association("Repositories").Append(&repository)
		if err != nil {
			logrus.WithError(err).Errorf("Failed to add repository %s for %s team", repository.Name, team.Name)
			return
		}
	}
}
