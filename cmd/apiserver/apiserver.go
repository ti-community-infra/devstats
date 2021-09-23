package main

import (
	"fmt"
	"net/http"
	"strconv"

	"github.com/gin-gonic/gin"
	"github.com/ti-community-infra/devstats/internal/pkg/api"
	"github.com/ti-community-infra/devstats/internal/pkg/identifier"
	"github.com/ti-community-infra/devstats/internal/pkg/lib"
	"github.com/ti-community-infra/devstats/internal/pkg/storage/model"
	"gorm.io/gorm"
	"gorm.io/gorm/clause"
)

func main() {
	var ctx identifier.Ctx
	err := ctx.Init()
	lib.FatalOnError(err)

	// Init database clients based on the project config.
	projectDBs := make(map[string]*gorm.DB)
	projectConfigs := lib.LoadProjectConfigFromFile(ctx.DataDir + ctx.ProjectsYaml)
	for _, config := range projectConfigs {
		port, err := strconv.Atoi(ctx.PgPort)
		lib.FatalOnError(err)
		conn, err := lib.NewConn("postgresql", ctx.PgHost, port, ctx.PgUser, ctx.PgPass, config.PDB)
		lib.FatalOnError(err)
		projectDBs[config.Slug] = conn
	}

	// Init database client connected to the identifier database.
	identifierDB, err := lib.NewConn(ctx.IDDbDialect, ctx.IDDbHost, ctx.IDDbPort, ctx.IDDbUser, ctx.IDDbPass, ctx.IDDbName)
	lib.FatalOnError(err)

	// Make sure the project info in the database.
	for _, config := range projectConfigs {
		var proj model.Project
		proj.Name = config.Slug
		proj.DisplayName = config.FullName
		identifierDB.Clauses(clause.OnConflict{
			Columns: []clause.Column{
				{Name: "name"},
			},
			DoNothing: true,
		}).Create(&proj)
	}

	// Init HTTP Router.
	router := gin.Default()

	// Handle /projects endpoint.
	projectHandler := api.ProjectHandler{}
	projectHandler.Init(identifierDB, projectDBs)

	router.GET("/projects/", func(c *gin.Context) {
		projects, err := projectHandler.GetProjects()
		if err != nil {
			msg := fmt.Sprintf("Failed to get projects.")
			api.ErrorMsg(c, 500, err, msg)
			return
		}
		c.JSON(http.StatusOK, &projects)
	})

	router.GET("/projects/:project/", func(c *gin.Context) {
		projectName := c.Param("project")
		project, err := projectHandler.GetProject(projectName)
		if err != nil {
			msg := fmt.Sprintf("Failed to get project %s detail.", projectName)
			api.ErrorMsg(c, 500, err, msg)
			return
		}
		c.JSON(http.StatusOK, &project)
	})

	// Handle /teams endpoint.
	teamHandler := api.TeamHandler{}
	teamHandler.Init(identifierDB, projectDBs)

	router.GET("/teams/", func(c *gin.Context) {
		teams, err := teamHandler.GetTeams()
		if err != nil {
			msg := fmt.Sprintf("Failed to get teams.")
			api.ErrorMsg(c, 500, err, msg)
			return
		}
		c.JSON(http.StatusOK, &teams)
	})

	router.GET("/teams/:team_name/", func(c *gin.Context) {
		teamName := c.Param("team_name")
		team, err := teamHandler.GetTeam(teamName)
		if err != nil {
			msg := fmt.Sprintf("Failed to get team %s.", teamName)
			api.ErrorMsg(c, 500, err, msg)
			return
		}
		c.JSON(http.StatusOK, &team)
	})

	// Handle /members endpoint.
	router.GET("/members/", func(c *gin.Context) {
		// Check if the level parameter.
		level, ok := c.GetQuery("level")
		if ok && level != "maintainer" && level != "committer" && level != "reviewer" {
			e := fmt.Errorf("wrong level parameter: %s", level)
			api.ErrorMsg(c, 500, e, "level only support `maintainer`, `committer` or `reviewer`.")
			return
		}

		members, _ := teamHandler.GetMembers(level)
		if err != nil {
			msg := fmt.Sprintf("Failed to get members.")
			api.ErrorMsg(c, 500, err, msg)
			return
		}
		c.JSON(http.StatusOK, &members)
	})

	// Handle /contributors endpoint.
	contributorHandler := api.ContributorHandler{}
	contributorHandler.Init(identifierDB, projectDBs)

	router.GET("/projects/:project/contributors/", func(c *gin.Context) {
		projectName := c.Param("project")
		includeBots, _ := strconv.ParseBool(c.Query("include_bots"))

		// Check if the order parameter.
		order := c.Query("order")
		if len(order) != 0 && order != api.ContributorLoginOrder && order != api.ContributorPRCountOrder {
			e := fmt.Errorf("wrong order parameter: %s", order)
			api.ErrorMsg(c, 400, e, "Wrong order parameter, order only support `login` or `pr_count`.")
			return
		}

		// Check if the direction parameter.
		direction := c.Query("direction")
		if len(direction) != 0 && direction != api.DirectionAsc && direction != api.DirectionDesc {
			e := fmt.Errorf("wrong direction parameter: %s", direction)
			api.ErrorMsg(c, 400, e, "Wrong direction parameter, direction only support `asc` or `desc`.")
			return
		}

		contributors, err := contributorHandler.GetContributors(projectName, includeBots, order, direction)
		if err != nil {
			msg := fmt.Sprintf("Failed to get contributors.")
			api.ErrorMsg(c, 500, err, msg)
			return
		}
		c.JSON(http.StatusOK, &contributors)
	})

	err = router.Run()
	lib.FatalOnError(err)
}
