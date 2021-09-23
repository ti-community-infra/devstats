package lib

import (
	"io/ioutil"
	"os"
	"sort"
	"strings"
	"time"

	"gopkg.in/yaml.v2"
)

// AllProjects contain all projects data
type AllProjects struct {
	Projects map[string]Project `yaml:"projects"`
}

// Project contain mapping from project name to its command line used to sync it
type Project struct {
	Slug             string
	CommandLine      []string          `yaml:"command_line"`
	StartDate        *time.Time        `yaml:"start_date"`
	PDB              string            `yaml:"psql_db"`
	Disabled         bool              `yaml:"disabled"`
	MainRepo         string            `yaml:"main_repo"`
	AnnotationRegexp string            `yaml:"annotation_regexp"`
	Order            int               `yaml:"order"`
	JoinDate         *time.Time        `yaml:"join_date"`
	FilesSkipPattern string            `yaml:"files_skip_pattern"`
	Env              map[string]string `yaml:"env"`
	FullName         string            `yaml:"name"`
	Status           string            `yaml:"status"`
	SharedDB         string            `yaml:"shared_db"`
	IncubatingDate   *time.Time        `yaml:"incubating_date"`
	GraduatedDate    *time.Time        `yaml:"graduated_date"`
	ArchivedDate     *time.Time        `yaml:"archived_date"`
	SyncProbability  *float64          `yaml:"sync_probabilty"`
	ProjectScale     *float64          `yaml:"project_scale"`
}

func LoadProjectConfigFromFile(projectYamlPath string) []Project {
	data, err := ioutil.ReadFile(projectYamlPath)
	FatalOnError(err)

	var allProject AllProjects
	err = yaml.Unmarshal(data, &allProject)
	FatalOnError(err)

	projects := make([]Project, 0)
	for slug, project := range allProject.Projects {
		project.Slug = slug
		projects = append(projects, project)
	}

	return projects
}

// ExcludedForProject - checks if metric defines project, if so then:
// if metric's project is XYZ and current project is XYZ then calculate this metric
// if metric's project is !XYZ and current project is *not* XYZ then calculate this metric
func ExcludedForProject(currentProject, metricProject string) bool {
	if metricProject == "" || currentProject == "" {
		return false
	}
	if metricProject[:1] == "!" {
		metricProject = metricProject[1:]
		if currentProject == metricProject {
			return true
		}
		return false
	}
	if currentProject != metricProject {
		return true
	}
	return false
}

// GetProjectsList return list of projects to process
// It sorts them according to projects.yaml order
// Handles disabled/enabled projects
// Handles ONLY="project1 project2 ... projectN" env
func GetProjectsList(ctx *Ctx, projects *AllProjects) (names []string, projs []Project) {
	if projects == nil {
		Fatalf("GetProjectsList: projects is nil")
	}
	// Order projects
	orders := []int{}
	projectsMap := make(map[int]string)

	// Handle disabled/enabled
	for name, proj := range projects.Projects {
		if IsProjectDisabled(ctx, name, proj.Disabled) {
			continue
		}
		orders = append(orders, proj.Order)
		projectsMap[proj.Order] = name
	}
	sort.Ints(orders)

	// Support ONLY="proj1 proj2 ... projN"
	only := make(map[string]struct{})
	onlyS := os.Getenv("ONLY")
	bOnly := false
	if onlyS != "" {
		onlyA := strings.Split(onlyS, " ")
		for _, item := range onlyA {
			if item == "" {
				continue
			}
			only[item] = struct{}{}
		}
		bOnly = true
	}

	// Order + ONLY
	for _, order := range orders {
		name := projectsMap[order]
		if bOnly {
			_, ok := only[name]
			if !ok {
				continue
			}
		}
		proj := projects.Projects[name]
		names = append(names, name)
		projs = append(projs, proj)
	}
	return
}

// IsProjectDisabled - checks if project is disabled or not:
// fullName comes from makeOldRepoName for pre-2015 data!
// yamlDisabled (this is from projects.yaml - can be true or false)
// it also checks context (which can override `disabled: true` from projects.yaml)
// +pro1,-pro2 creates map {"pro1":true, "pro2":false}
func IsProjectDisabled(ctx *Ctx, proj string, yamlDisabled bool) bool {
	override, ok := ctx.ProjectsOverride[proj]
	// No override for this project - just return YAML property value
	if !ok {
		return yamlDisabled
	}
	// If project override present then true means NOT disabled, and false means disabled
	return !override
}
