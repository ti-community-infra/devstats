package identifier

import (
	"context"
	"errors"
	"fmt"
	"os"
	"strconv"
	"sync"
	"time"

	"github.com/google/go-github/github"
	"github.com/patrickmn/go-cache"
	"github.com/sirupsen/logrus"
	"github.com/ti-community-infra/devstats/internal/pkg/lib"
)

/*  GitHub Client  */

type GitHubClient struct {
	ctx         *Ctx
	gcs         []*github.Client
	ghCtx       context.Context
	mtx         sync.Mutex
	log         *logrus.Entry
	memCache    *cache.Cache
	clientIndex int
	maxRetry    int
}

type GitHubGetUserResult struct {
	User github.User
	Err  string
}

type GitHubGetRepositoryResult struct {
	Repository github.Repository
	Err        string
}

func (c *GitHubClient) Init(ctx *Ctx, log *logrus.Entry, cache *cache.Cache) error {
	ghCtx, githubClients := lib.GHClient(&ctx.Ctx)
	c.gcs = githubClients
	c.mtx = sync.Mutex{}
	c.ctx = ctx
	c.ghCtx = ghCtx
	c.clientIndex = -1
	c.memCache = cache
	c.log = log
	c.maxRetry = ctx.MaxGHAPIRetry
	return nil
}

func (c *GitHubClient) GetUserByID(id int64) (*github.User, *github.Response, error) {
	// Try to get results from cache.
	cacheKey := "github-get-user-by-id-result-" + strconv.Itoa(int(id))
	if c.memCache != nil {
		resultCached, ok := c.memCache.Get(cacheKey)
		if ok {
			result := resultCached.(GitHubGetUserResult)
			if len(result.Err) == 0 {
				// Notice: The result obtained by caching will not contain the response.
				return &result.User, nil, nil
			}
			return nil, nil, errors.New(result.Err)
		}
	}

	// Support failure retry.
	for try := 1; try <= c.maxRetry; try++ {
		hint, _, remain, waitPeriod := lib.GetRateLimits(c.ghCtx, &c.ctx.Ctx, c.gcs, true)
		if remain[hint] <= c.ctx.MinGHAPIPoints {
			if waitPeriod[hint].Seconds() <= float64(c.ctx.MaxGHAPIWaitSeconds) {
				time.Sleep(time.Duration(1) * time.Second)
				time.Sleep(waitPeriod[hint])
				continue
			} else {
				c.log.Fatalf("API limit reached while getting issue data, aborting, don't want to wait %v", waitPeriod[hint])
				os.Exit(1)
			}
		}
		client := c.gcs[hint]
		user, res, err := client.Users.GetByID(c.ghCtx, id)

		if err != nil {
			c.log.Errorf("Failed to get user by id %d, retrying %d/%d.", id, try, c.maxRetry)
			continue
		} else {
			if c.memCache != nil {
				resultWithoutError := GitHubGetUserResult{
					User: *user,
					Err:  "",
				}
				c.memCache.Set(cacheKey, resultWithoutError, cache.DefaultExpiration)
			}
			return user, res, nil
		}
	}

	// Cache the error result.
	err := fmt.Errorf("failed to get user by id %d, it still fails after %d retries", id, c.maxRetry)
	if c.memCache != nil {
		resultWithError := GitHubGetUserResult{
			Err: err.Error(),
		}
		c.memCache.Set(cacheKey, resultWithError, cache.DefaultExpiration)
	}

	return nil, nil, err
}

func (c *GitHubClient) GetUserByLogin(login string) (*github.User, *github.Response, error) {
	// Try to get results from cache.
	cacheKey := "github-get-user-by-login-result-" + login
	if c.memCache != nil {
		resultCached, ok := c.memCache.Get(cacheKey)
		if ok {
			result := resultCached.(GitHubGetUserResult)
			if len(result.Err) == 0 {
				// Notice: The result obtained by caching will not contain the response.
				return &result.User, nil, nil
			}
			return nil, nil, errors.New(result.Err)
		}
	}

	// Support failure retry.
	for try := 1; try <= c.maxRetry; try++ {
		hint, _, remain, waitPeriod := lib.GetRateLimits(c.ghCtx, &c.ctx.Ctx, c.gcs, true)
		if remain[hint] <= c.ctx.MinGHAPIPoints {
			if waitPeriod[hint].Seconds() <= float64(c.ctx.MaxGHAPIWaitSeconds) {
				time.Sleep(time.Duration(1) * time.Second)
				time.Sleep(waitPeriod[hint])
				continue
			} else {
				c.log.Fatalf("API limit reached while getting issue data, aborting, don't want to wait %v", waitPeriod[hint])
				os.Exit(1)
			}
		}
		client := c.gcs[hint]
		user, res, err := client.Users.Get(c.ghCtx, login)

		if err != nil {
			c.log.Errorf("Failed to get user by login %s, retrying %d/%d.", login, try, c.maxRetry)
			continue
		} else {
			if c.memCache != nil {
				resultWithoutError := GitHubGetUserResult{
					User: *user,
					Err:  "",
				}
				c.memCache.Set(cacheKey, resultWithoutError, cache.DefaultExpiration)
			}
			return user, res, nil
		}
	}

	// Cache the error result.
	err := fmt.Errorf("failed to get user by login %s, it still fails after %d retries", login, c.maxRetry)
	if c.memCache != nil {
		resultWithError := GitHubGetUserResult{
			Err: err.Error(),
		}
		c.memCache.Set(cacheKey, resultWithError, cache.DefaultExpiration)
	}

	return nil, nil, err
}

func (c *GitHubClient) GetRepository(owner, repo string) (*github.Repository, *github.Response, error) {
	// Try to get results from cache.
	cacheKey := "github-repository-result-" + owner + "-" + repo
	if c.memCache != nil {
		resultCached, ok := c.memCache.Get(cacheKey)
		if ok {
			result := resultCached.(GitHubGetRepositoryResult)
			if len(result.Err) == 0 {
				// Notice: The result obtained by caching will not contain the response.
				return &result.Repository, nil, nil
			}
			return nil, nil, errors.New(result.Err)
		}
	}

	// Support failure retry.
	for try := 1; try <= c.maxRetry; try++ {
		hint, _, remain, waitPeriod := lib.GetRateLimits(c.ghCtx, &c.ctx.Ctx, c.gcs, true)
		if remain[hint] <= c.ctx.MinGHAPIPoints {
			if waitPeriod[hint].Seconds() <= float64(c.ctx.MaxGHAPIWaitSeconds) {
				time.Sleep(time.Duration(1) * time.Second)
				time.Sleep(waitPeriod[hint])
				continue
			} else {
				c.log.Fatalf("API limit reached while getting issue data, aborting, don't want to wait %v", waitPeriod[hint])
				os.Exit(1)
			}
		}
		client := c.gcs[hint]
		repository, res, err := client.Repositories.Get(c.ghCtx, owner, repo)

		if err != nil {
			c.log.Errorf(
				"Failed to get repository by repo name %s/%s, retrying %d/%d.",
				owner, repo, try, c.maxRetry,
			)
			continue
		} else {
			if c.memCache != nil {
				resultWithoutError := GitHubGetRepositoryResult{
					Repository: *repository,
					Err:        "",
				}
				c.memCache.Set(cacheKey, resultWithoutError, cache.DefaultExpiration)
			}
			return repository, res, nil
		}
	}

	// Cache the error result.
	err := fmt.Errorf(
		"failed to get repository by repo name %s/%s, it still fails after %d retries",
		owner, repo, c.maxRetry,
	)
	if c.memCache != nil {
		resultWithError := GitHubGetUserResult{
			Err: err.Error(),
		}
		c.memCache.Set(cacheKey, resultWithError, cache.DefaultExpiration)
	}

	return nil, nil, err
}
