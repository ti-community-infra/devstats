package api

import (
	"fmt"
	"sort"
	"strings"
	"time"

	"github.com/ti-community-infra/devstats/internal/pkg/storage/model"
	"gorm.io/gorm"
)

type TeamItem struct {
	ID          uint        `json:"id"`
	Name        string      `json:"name"`
	Description string      `json:"description"`
	URL         string      `json:"url"`
	Project     ProjectItem `json:"project"`
}

type ProjectItem struct {
	ID          uint   `json:"id"`
	Name        string `json:"name"`
	DisplayName string `json:"display_name"`
}

type TeamDetail struct {
	Name         string               `json:"name"`
	Description  string               `json:"description"`
	Maintainers  []TeamMemberItem     `json:"maintainers"`
	Committers   []TeamMemberItem     `json:"committers"`
	Reviewers    []TeamMemberItem     `json:"reviewers"`
	Repositories []TeamRepositoryItem `json:"repositories"`
}

type TeamMemberItem struct {
	ID    uint   `json:"id"`
	Login string `json:"login"`
	Name  string `json:"name"`
}

type TeamRepositoryItem struct {
	ID    uint   `json:"id"`
	Owner string `json:"owner"`
	Name  string `json:"name"`
}

type MemberItem struct {
	GitHubID         uint                  `json:"github_id"`
	GitHubLogin      string                `json:"github_login"`
	Name             string                `json:"name"`
	ParticipateTeams []ParticipateTeamItem `json:"participate_teams"`
}

type ParticipateTeamItem struct {
	TeamID         uint      `json:"team_id"`
	TeamName       string    `json:"team_name"`
	Level          string    `json:"level"`
	JoinDate       time.Time `json:"join_date"`
	LastUpdateDate time.Time `json:"last_update_date"`
}

type TeamHandler struct {
	BaseURL      string
	identifierDB *gorm.DB
	projectDBs   map[string]*gorm.DB
}

func (h *TeamHandler) Init(identifierDB *gorm.DB, projectDBs map[string]*gorm.DB) {
	h.identifierDB = identifierDB
	h.projectDBs = projectDBs
}

func (h *TeamHandler) GetTeams() ([]TeamItem, error) {
	var teams []model.Team
	err := h.identifierDB.Preload("Project").Find(&teams).Error
	if err != nil {
		return nil, err
	}

	var teamItems []TeamItem
	for _, team := range teams {
		var teamItem TeamItem
		teamItem.ID = team.ID
		teamItem.Name = team.Name
		teamItem.Description = team.Description
		teamItem.URL = fmt.Sprintf("%s/teams/%s", h.BaseURL, team.Name)

		var projectItem ProjectItem
		projectItem.ID = team.Project.ID
		projectItem.Name = team.Project.Name
		projectItem.DisplayName = team.Project.DisplayName
		teamItem.Project = projectItem

		teamItems = append(teamItems, teamItem)
	}

	return teamItems, nil
}

func (h *TeamHandler) GetTeam(teamName string) (*TeamDetail, error) {
	var team model.Team
	err := h.identifierDB.Preload("Repositories").Where("name = ?", teamName).Find(&team).Error
	if err != nil {
		return nil, err
	}

	var teamMembers []model.TeamMember
	err = h.identifierDB.Preload("UniqueIdentity").Where("team_id = ?", team.ID).Find(&teamMembers).Error
	if err != nil {
		return nil, err
	}

	// Team information.
	var teamDetail TeamDetail
	teamDetail.Name = team.Name
	teamDetail.Description = team.Description

	// Reviewers.
	teamReviewers := make([]TeamMemberItem, 0)
	for _, member := range teamMembers {
		var teamReviewer TeamMemberItem
		teamReviewer.Name = member.UniqueIdentity.Name
		teamReviewer.Login = member.DupGitHubLogin
		teamReviewer.ID = member.DupGitHubID
		teamReviewers = append(teamReviewers, teamReviewer)
	}
	teamDetail.Reviewers = teamReviewers

	// Committers.
	teamCommitters := make([]TeamMemberItem, 0)
	for _, member := range teamMembers {
		var teamCommitter TeamMemberItem
		teamCommitter.Name = member.UniqueIdentity.Name
		teamCommitter.Login = member.DupGitHubLogin
		teamCommitter.ID = member.DupGitHubID
		teamCommitters = append(teamCommitters, teamCommitter)
	}
	teamDetail.Committers = teamCommitters

	// Maintainers.
	teamMaintainers := make([]TeamMemberItem, 0)
	for _, member := range teamMembers {
		var teamMaintainer TeamMemberItem
		teamMaintainer.Name = member.UniqueIdentity.Name
		teamMaintainer.Login = member.DupGitHubLogin
		teamMaintainer.ID = member.DupGitHubID
		teamMaintainers = append(teamCommitters, teamMaintainer)
	}
	teamDetail.Maintainers = teamMaintainers

	// Repositories
	teamRepositories := make([]TeamRepositoryItem, 0)
	for _, repository := range team.Repositories {
		var teamRepository TeamRepositoryItem
		teamRepository.ID = repository.ID
		teamRepository.Name = repository.Name
		teamRepository.Owner = repository.Owner
		teamRepositories = append(teamRepositories, teamRepository)
	}
	teamDetail.Repositories = teamRepositories

	return &teamDetail, nil
}

func (h *TeamHandler) GetMembers(level string) ([]MemberItem, error) {
	var members []struct {
		GitHubID       uint   `gorm:"column:github_id"`
		GitHubLogin    string `gorm:"column:github_login"`
		Name           string
		TeamID         uint
		TeamName       string
		Level          string
		JoinDate       time.Time
		LastUpdateDate time.Time
	}
	query := h.identifierDB.Raw("select " +
		"gu.id as github_id, gu.login as github_login, ui.name as name, t.id as team_id, " +
		"t.name as team_name, tm.level as level, tm.join_date, tm.last_update_date " +
		"from " +
		"team_members tm " +
		"left join teams t on t.id = tm.team_id " +
		"left join unique_identities ui on tm.uuid = ui.uuid " +
		"left join github_users gu on ui.uuid = gu.uuid ",
	)
	err := query.Find(&members).Error
	if err != nil {
		return nil, err
	}

	memberItemMap := make(map[uint]MemberItem, 0)
	for _, member := range members {
		var memberItem MemberItem

		if memberFound, ok := memberItemMap[member.GitHubID]; ok {
			memberItem = memberFound
		} else {
			memberItem.GitHubID = member.GitHubID
			memberItem.GitHubLogin = member.GitHubLogin
			memberItem.Name = member.Name
			memberItem.ParticipateTeams = make([]ParticipateTeamItem, 0)
		}

		// Skip the no match level.
		if len(level) != 0 && member.Level != level {
			continue
		}

		participateTeam := ParticipateTeamItem{
			TeamID:         member.TeamID,
			TeamName:       member.TeamName,
			Level:          member.Level,
			JoinDate:       member.JoinDate,
			LastUpdateDate: member.LastUpdateDate,
		}
		memberItem.ParticipateTeams = append(memberItem.ParticipateTeams, participateTeam)
		memberItemMap[member.GitHubID] = memberItem
	}

	// Convert to array.
	memberItems := make([]MemberItem, 0)
	for _, item := range memberItemMap {
		memberItems = append(memberItems, item)
	}

	// Order by GitHub Login, from A to Z.
	sort.Slice(memberItems, func(i, j int) bool {
		return strings.Compare(memberItems[i].GitHubLogin, memberItems[j].GitHubLogin) < 0
	})

	return memberItems, nil
}
