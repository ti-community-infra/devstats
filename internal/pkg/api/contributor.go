package api

import (
	"fmt"
	"sort"
	"strings"

	"github.com/sirupsen/logrus"
	"github.com/ti-community-infra/devstats/internal/pkg/lib"
	"gorm.io/gorm"
)

type ContributorItem struct {
	GitHubID                uint                    `json:"github_id"`
	GitHubLogin             string                  `json:"github_login"`
	ParticipateRepositories []ParticipateRepository `json:"participate_repositories"`
	PRCount                 uint                    `json:"pr_count"`
}

type ParticipateRepository struct {
	RepoID   uint   `json:"repo_id"`
	RepoName string `json:"repo_name"`
	PRCount  uint   `json:"pr_count"`
}

const (
	ContributorLoginOrder   = "login"
	ContributorPRCountOrder = "pr_count"
)

var botLogins = []string{
	"ti-chi-bot", "ti-srebot", "sre-bot", "ti-community-prow-bot", "dependabot[bot]",
	"tidb-dashboard-bot", "fossabot",
}

type ContributorHandler struct {
	identifierDB *gorm.DB
	projectDBs   map[string]*gorm.DB
	botLoginSet  lib.StringSet
	BaseURL      string
}

func (h *ContributorHandler) Init(identifierDB *gorm.DB, projectDBs map[string]*gorm.DB, baseURL string) {
	h.identifierDB = identifierDB
	h.projectDBs = projectDBs
	h.botLoginSet = lib.FromArray(botLogins)
	h.BaseURL = baseURL
}

func (h *ContributorHandler) GetContributors(
	projectName string, includeBots bool, order, direction string,
) ([]ContributorItem, error) {
	projDB, ok := h.projectDBs[projectName]
	if !ok {
		logrus.Errorf("There are no project named %s.", projectName)
		return nil, fmt.Errorf("there are no project named %s", projectName)
	}

	var contributionItems []struct {
		GitHubID    uint   `gorm:"column:github_id"`
		GitHubLogin string `gorm:"column:github_login"`
		RepoID      uint   `gorm:"column:repo_id"`
		RepoName    string `gorm:"column:repo_name"`
		PRCount     uint   `gorm:"column:pr_count"`
	}
	projDB.Raw(`
with pr_counts as (
    select
        user_id, repo_id, repo_name, count(distinct pr_id) as cnt
    from (
        select
            distinct on(pr.id)
            pr.id as pr_id,
            user_id as user_id,
            dup_user_login as user_login,
            dup_repo_id as repo_id,
            r.name as repo_name,
            row_number() over (partition by pr.id order by r.updated_at desc) as rank
        from
            gha_pull_requests pr
            left join gha_repos r on pr.dup_repo_id = r.id
        where
            merged_at is not null
     ) sub
    where rank = 1
    group by
        user_id, repo_id, repo_name
), contributor_with_current_login as (
    select
        user_id, user_login
    from (
             select
                 user_id as user_id,
                 dup_user_login as user_login,
                 row_number() over (partition by user_id order by pr.updated_at desc) as rank
             from
                 gha_pull_requests pr
             where
                 merged_at is not null
    ) sub
    where rank = 1
)
select
    ccl.user_id as github_id, ccl.user_login as github_login, repo_id, repo_name, cnt as pr_count
from
    contributor_with_current_login ccl
    left join pr_counts pc on ccl.user_id = pc.user_id
	;`).Scan(&contributionItems)

	contributorMap := make(map[uint]ContributorItem)
	for _, contribution := range contributionItems {
		var contributorItem ContributorItem

		if existedContributorItem, ok := contributorMap[contribution.GitHubID]; ok {
			contributorItem = existedContributorItem
		} else {
			contributorItem.GitHubID = contribution.GitHubID
			contributorItem.GitHubLogin = contribution.GitHubLogin
			contributorItem.ParticipateRepositories = make([]ParticipateRepository, 0)
		}

		var participateRepository ParticipateRepository
		participateRepository.RepoID = contribution.RepoID
		participateRepository.RepoName = contribution.RepoName
		participateRepository.PRCount = contribution.PRCount

		contributorItem.ParticipateRepositories = append(contributorItem.ParticipateRepositories, participateRepository)
		contributorItem.PRCount = contributorItem.PRCount + contribution.PRCount
		contributorMap[contribution.GitHubID] = contributorItem
	}

	// Convert to array.
	contributorItems := make([]ContributorItem, 0)
	for _, item := range contributorMap {
		if !includeBots {
			// Skip the Bots.
			if _, ok := h.botLoginSet[item.GitHubLogin]; ok {
				continue
			}
		}
		contributorItems = append(contributorItems, item)
	}

	// Default order is by GitHub login.
	if len(order) == 0 || order == ContributorLoginOrder {
		// Order by GitHub Login, default direction is asc, from A to Z.
		sort.Slice(contributorItems, func(i, j int) bool {
			if direction == DirectionDesc {
				return strings.Compare(contributorItems[i].GitHubLogin, contributorItems[j].GitHubLogin) > 0
			}
			return strings.Compare(contributorItems[i].GitHubLogin, contributorItems[j].GitHubLogin) < 0
		})
	} else if order == ContributorPRCountOrder {
		// Order by PR Count, default direction is desc.
		sort.Slice(contributorItems, func(i, j int) bool {
			if direction == DirectionAsc {
				return contributorItems[i].PRCount < contributorItems[j].PRCount
			}
			return contributorItems[i].PRCount > contributorItems[j].PRCount
		})
	}

	return contributorItems, nil
}
