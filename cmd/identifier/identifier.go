package main

import (
	"encoding/gob"
	"os"
	"strconv"
	"time"

	"github.com/google/go-github/github"
	"github.com/patrickmn/go-cache"
	"github.com/sirupsen/logrus"
	"github.com/ti-community-infra/devstats/internal/pkg/identifier"
	"github.com/ti-community-infra/devstats/internal/pkg/lib"
)

func main() {
	// Init context.
	var ctx identifier.Ctx
	err := ctx.Init()
	lib.FatalOnError(err)

	// Init logger.
	log := logrus.WithField("program", "identifier")

	// Init database client.
	db, err := lib.NewConn(ctx.IDDbDialect, ctx.IDDbHost, ctx.IDDbPort, ctx.IDDbUser, ctx.IDDbPass, ctx.IDDbName)
	lib.FatalOnError(err)

	// Init database client used to import data.
	pgPort, err := strconv.Atoi(ctx.PgPort)
	lib.FatalOnError(err)
	dataSource, err := lib.NewConn(
		"postgresql", ctx.PgHost, pgPort, ctx.PgUser,
		ctx.PgPass, ctx.PgDB,
	)
	lib.FatalOnError(err)

	// Init the memory cache.
	memCache := cache.New(2*24*time.Hour, 4*24*time.Hour)

	gob.Register(github.Response{})
	gob.Register(github.User{})
	gob.Register(github.RateLimits{})
	gob.Register(identifier.GitHubGetUserResult{})
	gob.Register(identifier.LocationCacheEntry{})
	gob.Register(lib.StringSet{})

	_, err = os.Stat(ctx.CacheFilePath)
	if err != nil && !os.IsExist(err) {
		_, err := os.Create(ctx.CacheFilePath)
		if err != nil {
			panic(err)
		}
	}
	err = memCache.LoadFile(ctx.CacheFilePath)
	if err != nil && err.Error() != "EOF" {
		log.WithError(err).Errorf("Failed to load cache from file: %s", ctx.CacheFilePath)
		return
	}

	if !ctx.SkipAutoImportProfile {
		// Init GitHub Client.
		gc := identifier.GitHubClient{}
		err = gc.Init(&ctx, log, memCache)
		if err != nil {
			lib.FatalOnError(err)
			return
		}

		// Init Google Map Client.
		locationClient := identifier.LocationClient{}
		err = locationClient.Init(&ctx, log, memCache)
		if err != nil {
			lib.FatalOnError(err)
			return
		}

		// Init employee manager.
		employeeManager := identifier.EmployeeManager{}
		err = employeeManager.Init(ctx, log, memCache)
		if err != nil {
			log.WithError(err).Errorf("Failed to init employee manager.")
			return
		}

		identifier.AutoImportProfile(log, &ctx, db, dataSource, &gc, &locationClient, &employeeManager, memCache)

		// Save the cache to file.
		err = memCache.SaveFile(ctx.CacheFilePath)
		if err != nil {
			log.WithError(err).Errorf("Failed to save the memory cache to file: %s", ctx.CacheFilePath)
			return
		}
	}

	if !ctx.SkipOutputGitHubUserJSON {
		identifier.OutputGitHubUserToJSON(log, &ctx, db)
	}
}
