package api

import (
	"errors"
	"fmt"

	"github.com/ti-community-infra/devstats/internal/pkg/storage/model"
	"gorm.io/gorm"
)

type ProjectDetailStats struct {
	PullRequests uint `json:"pull_requests"`
	Issues       uint `json:"issues"`
	Repositories uint `json:"repositories"`
	Contributors uint `json:"contributors"`
}

type ProjectDetail struct {
	DisplayName     string             `json:"display_name"`
	Name            string             `json:"name"`
	URL             string             `json:"url"`
	ContributorsURL string             `json:"contributor_url"`
	Stats           ProjectDetailStats `json:"stats,omitempty"`
}

type ProjectHandler struct {
	identifierDB *gorm.DB
	projectDBs   map[string]*gorm.DB
	BaseURL      string
}

func (h *ProjectHandler) Init(identifierDB *gorm.DB, projectDBs map[string]*gorm.DB, baseURL string) {
	h.identifierDB = identifierDB
	h.projectDBs = projectDBs
	h.BaseURL = baseURL
}

func (h *ProjectHandler) GetProjects() ([]ProjectDetail, error) {
	var projects []model.Project
	err := h.identifierDB.Find(&projects).Error
	if err != nil {
		return nil, err
	}

	projectDetails := make([]ProjectDetail, 0)
	for _, project := range projects {
		var projectDetail ProjectDetail
		projectDetail.Name = project.Name
		projectDetail.DisplayName = project.DisplayName
		projectDetail.URL = fmt.Sprintf("%s/projects/%s", h.BaseURL, project.Name)
		projectDetail.ContributorsURL = fmt.Sprintf("%s/projects/%s/contributors", h.BaseURL, project.Name)
		if projDB, ok := h.projectDBs[project.Name]; ok {
			projectDetail.Stats = getProjectStat(projDB)
		}
		projectDetails = append(projectDetails, projectDetail)
	}

	return projectDetails, nil
}

func (h *ProjectHandler) GetProject(projectName string) (*ProjectDetail, error) {
	projDB, ok := h.projectDBs[projectName]
	if !ok {
		return nil, errors.New("failed to get project database")
	}

	var project model.Project
	err := h.identifierDB.Where("name = ?", projectName).First(&project).Error
	if err != nil {
		return nil, fmt.Errorf("failed to get project named %s", projectName)
	}

	var projectDetail ProjectDetail
	projectDetail.Name = project.Name
	projectDetail.DisplayName = project.DisplayName
	projectDetail.URL = fmt.Sprintf("%s/projects/%s", h.BaseURL, project.Name)
	projectDetail.ContributorsURL = fmt.Sprintf("%s/projects/%s/contributors", h.BaseURL, project.Name)
	projectDetail.Stats = getProjectStat(projDB)

	return &projectDetail, nil
}

func getProjectStat(projDB *gorm.DB) ProjectDetailStats {
	var stats ProjectDetailStats
	projDB.Raw("select count(distinct id) from gha_pull_requests;").Scan(&stats.PullRequests)
	projDB.Raw("select count(distinct id) from gha_issues where is_pull_request = false;").Scan(&stats.Issues)
	projDB.Raw("select count(distinct id) from gha_repos;").Scan(&stats.Repositories)
	projDB.Raw("select count(distinct user_id) from gha_pull_requests pr where merged_at is not null;").Scan(&stats.Contributors)
	return stats
}
