package identifier

import (
	"bytes"
	"context"
	"encoding/csv"
	"encoding/json"
	"errors"
	"fmt"
	"io/ioutil"
	"net/http"
	"regexp"
	"sort"
	"strings"
	"sync"
	"time"

	"github.com/aws/aws-sdk-go/aws"
	"github.com/aws/aws-sdk-go/aws/awserr"
	"github.com/aws/aws-sdk-go/aws/credentials"
	"github.com/aws/aws-sdk-go/aws/request"
	"github.com/aws/aws-sdk-go/aws/session"
	"github.com/aws/aws-sdk-go/service/s3"
	"github.com/chyroc/lark"
	"github.com/google/uuid"
	"github.com/patrickmn/go-cache"
	"github.com/sirupsen/logrus"
	"github.com/ti-community-infra/devstats/internal/pkg/lib"
	"github.com/ti-community-infra/devstats/internal/pkg/storage/model"
	"googlemaps.github.io/maps"
	"gopkg.in/yaml.v2"
	"gorm.io/gorm"
	"gorm.io/gorm/clause"
)

// GitHubUserFromJSON - single GitHub user entry from cncf/gitdm `github_users.json` JSON.
type GitHubUserFromJSON struct {
	Login string `json:"login"`
	// Email use ! instead of @ for email encoding.
	Email string `json:"email"`
	// Affiliation format: "YouTube < 2016-10-01, Google",
	Affiliation string `json:"affiliation,omitempty"`
	// Source valid values: "notfound": -20, "domain": -10, "": 0, "config": 10, "manual": 20, "user_manual": 30, "user": 40
	Source    string   `json:"source"`
	Name      string   `json:"name"`
	CountryID *string  `json:"country_id,omitempty"`
	Sex       *string  `json:"sex,omitempty"`
	SexProb   *float64 `json:"sex_prob,omitempty"`
	Tz        *string  `json:"tz,omitempty"`
	Age       *int     `json:"age,omitempty"`
}

const GitHubNoReplyEmailSuffix = "@users.noreply.github.com"

// OrgConfig is the data structure of organizations.yaml file.
type OrgConfig struct {
	OrgMappings []OrgMapping `yaml:"organizations"`
}

type OrgMapping struct {
	Name     string                 `yaml:"name"`
	Fullname string                 `yaml:"fullname"`
	Type     model.OrganizationType `yaml:"type"`
	Website  string                 `yaml:"website"`
	Patterns []string               `yaml:"patterns"`
	Domains  []model.OrgDomain      `yaml:"domains"`
}

/*  Location Client  */

// LocationClient - used to get formatted location address and country code.
type LocationClient struct {
	log       *logrus.Entry
	mapClient *maps.Client
	memCache  *cache.Cache
}

type LocationCacheEntry struct {
	FormattedAddress string
	CountryName      string
	CountryCode      string
}

const locationCacheKeyPrefix = "formatted-location-"

const locationCacheExpire = 365 * 24 * time.Hour

func (l *LocationClient) Init(ctx *Ctx, log *logrus.Entry, memCache *cache.Cache) error {
	mapClient, err := maps.NewClient(maps.WithAPIKey(ctx.GoogleMapAPIKey))
	if err != nil {
		return err
	}

	l.mapClient = mapClient
	l.memCache = memCache
	l.log = log

	return nil
}

func (l *LocationClient) FormattedLocation(location string) (string, string, string, error) {
	location = strings.TrimSpace(strings.ToLower(location))
	locationCacheKey := locationCacheKeyPrefix + location

	if len(location) == 0 {
		return "", "", "", errors.New("location is empty")
	}

	cacheEntry, ok := l.memCache.Get(locationCacheKey)
	if ok {
		result := cacheEntry.(LocationCacheEntry)
		l.log.Debugf("Location hit cache: %s %s %s", result.FormattedAddress, result.CountryCode, result.CountryName)
		if len(result.CountryName) == 0 && len(result.CountryCode) == 0 && len(result.FormattedAddress) == 0 {
			return "", "", "", errors.New("no matching locations were found")
		}
		return result.FormattedAddress, result.CountryCode, result.CountryName, nil
	}

	// Get country name and country code through Google Maps API.
	results, err := l.mapClient.Geocode(context.Background(), &maps.GeocodingRequest{
		Address: location,
	})

	if err != nil {
		return "", "", "", err
	}

	if len(results) == 0 {
		cacheResult := LocationCacheEntry{
			FormattedAddress: "",
			CountryCode:      "",
			CountryName:      "",
		}
		l.memCache.Set(locationCacheKey, cacheResult, locationCacheExpire)
		return "", "", "", errors.New("no matching locations were found")
	}

	match := results[0]
	formattedAddress := match.FormattedAddress
	countryName := ""
	countryCode := ""

	for _, component := range match.AddressComponents {
		isCountryPart := false
		for _, t := range component.Types {
			if t == "country" {
				isCountryPart = true
				break
			}
		}

		if isCountryPart {
			countryName = component.LongName
			countryCode = component.ShortName
			break
		}
	}

	if len(countryCode) == 0 {
		cacheResult := LocationCacheEntry{
			FormattedAddress: formattedAddress,
			CountryCode:      "",
			CountryName:      "",
		}
		l.memCache.Set(locationCacheKey, cacheResult, locationCacheExpire)
		return "", "", "", errors.New("failed to found country code")
	}

	cacheResult := LocationCacheEntry{
		FormattedAddress: formattedAddress,
		CountryCode:      countryCode,
		CountryName:      countryName,
	}
	l.memCache.Set(locationCacheKey, cacheResult, locationCacheExpire)

	return formattedAddress, countryCode, countryName, nil
}

/*  Employee Manager（Base on Lark） */

const GithubLoginAttrID string = "C-6934211695879389211"

const LarkCompany = "PingCAP"

const LarkContactGitHubLoginsCacheKey = "lark-contact-github-logins"

type EmployeeManager struct {
	background        context.Context
	log               *logrus.Entry
	larkClient        *lark.Lark
	memCache          *cache.Cache
	githubLogins      lib.StringSet
	tenantAccessToken string
}

func (m *EmployeeManager) Init(ctx Ctx, log *logrus.Entry, memCache *cache.Cache) error {
	m.log = log
	m.background = context.Background()
	m.githubLogins = make(lib.StringSet)
	m.memCache = memCache

	// Init lark client.
	cli := lark.New(lark.WithAppCredential(ctx.LarkAppID, ctx.LarkAppSecret))
	m.larkClient = cli

	// Get tenant access token.
	token, _, err := cli.Auth.GetTenantAccessToken(m.background)
	lib.FatalOnError(err)
	m.tenantAccessToken = token.Token

	return nil
}

// PrepareGitHubLogins - Get GitHub login from Lark contact.
func (m *EmployeeManager) PrepareGitHubLogins() error {
	background := context.Background()

	// Try to fetch GitHub logins from cache.
	larkUserCache, hit := m.memCache.Get(LarkContactGitHubLoginsCacheKey)
	if hit {
		githubLogins := larkUserCache.(lib.StringSet)
		m.log.Debugf("Hit the lark contact cache, found %d github logins.", len(githubLogins))
		m.githubLogins = githubLogins
		return nil
	}

	// Get all departments.
	rootDepartmentID := "0"
	departmentIDs := make([]string, 0)
	pageSize := int64(50)
	pageToken := ""
	isFetchChild := true

	for {
		req := &lark.GetDepartmentListReq{
			ParentDepartmentID: &rootDepartmentID,
			FetchChild:         &isFetchChild,
			PageSize:           &pageSize,
		}
		if len(pageToken) > 0 {
			req.PageToken = &pageToken
		}

		list, _, err := m.larkClient.Contact.GetDepartmentList(background, req, lark.WithUserAccessToken(m.tenantAccessToken))
		lib.FatalOnError(err)

		for _, item := range list.Items {
			departmentIDs = append(departmentIDs, item.OpenDepartmentID)
		}

		if list.HasMore {
			pageToken = list.PageToken
		} else {
			break
		}
	}

	// Get GitHub Logins.
	githubLogins := make(lib.StringSet)
	for _, departmentID := range departmentIDs {
		m.log.Infof("Fetch github login from department: %s", departmentID)

		// Get paging user info via api.
		pageToken = ""
		for {
			req := &lark.GetUserListReq{
				DepartmentID: &departmentID,
				PageSize:     &pageSize,
			}
			if len(pageToken) > 0 {
				req.PageToken = &pageToken
			}

			list, _, err := m.larkClient.Contact.GetUserList(background, req, lark.WithUserAccessToken(m.tenantAccessToken))
			lib.FatalOnError(err)

			for _, item := range list.Items {
				for _, attr := range item.CustomAttrs {
					if attr.ID == GithubLoginAttrID {
						githubLogin := attr.Value.Text
						githubLogins[githubLogin] = struct{}{}
					}
				}
			}

			if list.HasMore {
				pageToken = list.PageToken
			} else {
				break
			}
		}
	}

	m.githubLogins = githubLogins
	m.memCache.Set(LarkContactGitHubLoginsCacheKey, githubLogins, cache.DefaultExpiration)
	m.log.Infof("Found %d github login from lark contact.", len(m.githubLogins))

	return nil
}

// IsEmployeeLogin used to determine whether the given GitHub login is the employee's login
func (m *EmployeeManager) IsEmployeeLogin(githubLogin string) bool {
	if _, ok := m.githubLogins[githubLogin]; ok {
		return true
	}
	return false
}

// AutoImportProfile - Import GitHub user info from devstats and fetch their public profile information.
func AutoImportProfile(
	log *logrus.Entry, ctx *Ctx, db *gorm.DB, dataSource *gorm.DB,
	gc *GitHubClient, locationClient *LocationClient, employeeManager *EmployeeManager, memCache *cache.Cache,
) {
	// Ensure the existence of database structure and basic data.
	EnsureStructure(log, db)

	// Import the init data from file to database.
	loadInitData(log, ctx, db)

	// Get GitHub User profile from json file.
	githubUsersFromJSON := loadGitHubUsersFromJSON(ctx.GitHubUsersJSONSourcePath)
	log.Infof("Found %d GitHub user profile from json file.", len(githubUsersFromJSON))

	// Get employee GitHub logins.
	err := employeeManager.PrepareGitHubLogins()
	if err != nil {
		log.WithError(err).Errorf("Failed to prepare github logins from lark.")
		return
	}

	// Get existed organizations.
	startTime := time.Now()
	log.Infof("Establishing the mapping from pattern to org...")

	pattern2org := make(map[*regexp.Regexp]model.Organization)
	domain2org := make(map[string]model.Organization)

	var organizations []model.Organization
	db.Preload("Patterns").Preload("Domains").Where("invalid = ?", false).Find(&organizations)

	for _, organization := range organizations {
		for _, pattern := range organization.Patterns {
			reg, err := regexp.Compile("(?i)" + pattern.Pattern)
			if err != nil {
				log.WithError(err).Errorf("Failed to compile the org pattern: orgID=%d pattern=%s", organization.ID, pattern.Pattern)
				continue
			}
			pattern2org[reg] = organization
		}
		for _, domain := range organization.Domains {
			if len(domain.Name) != 0 && domain.Common == false {
				domain2org[domain.Name] = organization
			}
		}
	}

	endTime := time.Now()
	log.Infof("Established the mapping from pattern to org, cost time: %v.", endTime.Sub(startTime))

	// Get an existing unified identity.
	var uniqueIdentities []model.UniqueIdentity
	db.Preload("Country").Preload("Organizations").Preload("Projects").
		Preload("GitHubUsers").Find(&uniqueIdentities)

	// Import GitHub account from Devstats database.
	var actors []model.GhaActor
	err = dataSource.Preload("Names").Preload("Emails").
		Where("gha_actors.id in (select distinct actor_id from gha_events)").Find(&actors).Error
	lib.FatalOnError(err)
	log.Infof("Found %d external identities need to be importd.", len(actors))

	githubID2logins := make(map[uint]lib.StringSet)
	githubID2emails := make(map[uint]lib.StringSet)
	githubID2names := make(map[uint]lib.StringSet)

	for _, actor := range actors {
		githubID := actor.ID
		if githubID < 0 {
			continue
		}

		// GitHub login deduplication.
		logins, ok := githubID2logins[githubID]
		if !ok {
			logins = make(lib.StringSet)
		}
		logins[actor.Login] = struct{}{}
		githubID2logins[githubID] = logins

		// GitHub email deduplication.
		emails, ok := githubID2emails[githubID]
		if !ok {
			emails = make(lib.StringSet)
		}
		for _, email := range actor.Emails {
			emails[email.Email] = struct{}{}
		}
		githubID2emails[githubID] = emails

		// GitHub name deduplication.
		names, ok := githubID2names[githubID]
		if !ok {
			names = make(lib.StringSet)
		}
		for _, name := range actor.Names {
			names[name.Name] = struct{}{}
		}
		githubID2names[githubID] = names
	}

	log.Infof("Found %d github id from devstats datavase.", len(githubID2logins))

	// Merge the affiliation information, and only keep the affiliation with the highest priority.
	githubLogin2JsonUser := make(map[string]GitHubUserFromJSON)
	source2priority := map[string]int{
		"notfound": -20, "domain": -10, "": 0, "config": 10, "manual": 20, "user_manual": 30, "user": 40,
	}
	for _, newGitHubUser := range githubUsersFromJSON {
		source := strings.ToLower(newGitHubUser.Source)
		if source != "domain" && source != "config" && source != "manual" && source != "user_manual" && source != "user" {
			continue
		}
		login := newGitHubUser.Login

		if oldGitHubUser, ok := githubLogin2JsonUser[login]; ok {
			newSource := source
			newSourcePriority := source2priority[newSource]
			oldSource := strings.ToLower(oldGitHubUser.Source)
			oldSourcePriority := source2priority[oldSource]

			if newSourcePriority > oldSourcePriority {
				githubLogin2JsonUser[login] = newGitHubUser
			}
		} else {
			githubLogin2JsonUser[login] = newGitHubUser
		}
	}

	// Get via GitHub Profile.
	nGitHubIds := len(githubID2logins)
	i := 0

	nThreads := 0
	thrN := 16
	ch := make(chan bool)
	thMtx := sync.Mutex{}
	startTime = time.Now()

	for githubID, loginSet := range githubID2logins {
		go processUniqueIdentity(
			ch, &thMtx, db, log, gc, locationClient, employeeManager,
			githubID, loginSet, githubID2names, githubID2emails, pattern2org, domain2org,
			githubLogin2JsonUser,
		)

		// Save the cache to file.
		if i%100 == 0 || i == nGitHubIds-1 {
			log.Infof("Importing %d/%d GitHub Users.", i+1, nGitHubIds)
			err = memCache.SaveFile(ctx.CacheFilePath)
			if err != nil {
				log.WithError(err).Errorf("Failed to save the memory cache to file: %s", ctx.CacheFilePath)
				return
			}
			log.Infof("GitHub user cache stored to file.")
		}

		i++
		nThreads++
		if nThreads == thrN {
			<-ch
			nThreads--
		}
	}

	for nThreads > 0 {
		<-ch
		nThreads--
	}

	endTime = time.Now()
	log.Infof("Imported %d GitHub users, cost: %v.", nGitHubIds, endTime.Sub(startTime))
}

// EnsureStructure is used to ensure the table structure existed in the database.
func EnsureStructure(log *logrus.Entry, db *gorm.DB) {
	// Create data tables.
	err := db.AutoMigrate(
		&model.Project{},
		&model.Team{},
		&model.TeamMember{},
		&model.Repository{},
		&model.TeamMemberChangeLog{},
		&model.Country{},
		&model.UniqueIdentity{},
		&model.Organization{},
		&model.OrgDomain{},
		&model.OrgPattern{},
		&model.Enrollment{},
		&model.GitHubUser{},
		&model.GitHubUserEmail{},
		&model.GitHubUserLogin{},
		&model.GitHubUserName{},
	)
	if err != nil {
		log.WithError(err).Error("Failed to migrate.")
		lib.FatalOnError(err)
		return
	}

	err = db.SetupJoinTable(&model.UniqueIdentity{}, "Organizations", &model.Enrollment{})
	if err != nil {
		log.WithError(err).Errorln("Failed to setup join table: enrollments.")
		lib.FatalOnError(err)
		return
	}

	err = db.SetupJoinTable(&model.Team{}, "Members", &model.TeamMember{})
	if err != nil {
		log.WithError(err).Errorln("Failed to setup join table: team_members.")
		lib.FatalOnError(err)
		return
	}
}

// loadInitData is used to import the init data from file to database.
func loadInitData(log *logrus.Entry, ctx *Ctx, db *gorm.DB) {
	var haveImportInitData bool
	db.Raw(
		"select exists(select dt from gha_computed where metric = ?)", "identifier_init_data",
	).Scan(&haveImportInitData)

	if haveImportInitData {
		log.Infof("Skip import init data.")
		return
	}

	// Import country code to database.
	log.Infof("Importing country code...")
	countries, err := loadCountryCodesFromFile(ctx.CountryCodesFilePath)
	if err != nil {
		log.Fatalf("Failed import country codes from file.")
		panic(err)
	}
	for _, country := range countries {
		db.Clauses(clause.OnConflict{
			Columns: []clause.Column{
				{Name: "code"},
			},
			UpdateAll: true,
		}).Create(&country)
	}
	if err != nil {
		logrus.WithError(err).Errorf("Failed to import country codes to database.")
	} else {
		logrus.Infof("Importing country codes to database successfully.")
	}

	// Import organizations from yaml config file.
	orgConfig, err := loadOrgMappingsFromYaml(ctx.OrganizationsFilePath)
	if err != nil {
		log.WithError(err).Errorln("Failed to load org mapping config from yaml file.")
		return
	}
	orgMappings := orgConfig.OrgMappings
	nOrgMappings := len(orgMappings)
	startTime := time.Now()
	i := 0

	for _, mapping := range orgMappings {
		if i%100 == 0 || i == nOrgMappings-1 {
			log.Infof("Processing %d/%d Organization.", i+1, nOrgMappings)
		}
		i++

		// Find or create organization.
		var org model.Organization
		org.Name = mapping.Name
		org.Fullname = mapping.Fullname
		org.Website = mapping.Website
		org.Type = mapping.Type
		if isEducationOrgName(mapping.Name) {
			org.Type = model.OrgTypeEducation
		} else if mapping.Name == "Individual" {
			org.Type = model.OrgTypeIndividual
		} else if strings.HasPrefix(mapping.Name, "@") {
			org.Type = model.OrgTypeOpenSource
		}
		err := db.Preload("Patterns").Preload("Domains").
			Where("name = ?", org.Name, false).
			FirstOrCreate(&org).Error
		if err != nil || org.ID == 0 {
			log.WithError(err).Errorf("Failed to find or create organization: %s", org.Name)
			continue
		}

		// Import organization patterns.
		for _, pattern := range mapping.Patterns {
			if len(pattern) == 0 {
				continue
			}
			var orgPattern model.OrgPattern
			orgPattern.OrgID = org.ID
			orgPattern.Pattern = pattern
			db.Clauses(clause.OnConflict{
				Columns: []clause.Column{
					{Name: "org_id"}, {Name: "pattern"},
				},
				DoNothing: true,
			}).Create(&orgPattern)
		}

		// Import organization domains.
		for _, domain := range mapping.Domains {
			if len(domain.Name) == 0 {
				continue
			}
			domain.OrgID = org.ID
			db.Clauses(clause.OnConflict{
				Columns: []clause.Column{
					{Name: "org_id"}, {Name: "name"},
				},
				DoNothing: true,
			}).Create(&domain)
		}
	}

	endTime := time.Now()
	log.Infof("Imported %d organizations, cost time: %v.", len(orgMappings), endTime.Sub(startTime))

	db.Exec("insert into gha_computed(metric, dt) values(?, ?)", "identifier_init_data", time.Now())
}

// loadCountryCodesFromFile - get country code from csv file.
func loadCountryCodesFromFile(fileName string) ([]model.Country, error) {
	bytesFile, err := ioutil.ReadFile(fileName)
	r := csv.NewReader(strings.NewReader(string(bytesFile)))
	rows, _ := r.ReadAll()
	if err != nil {
		return nil, fmt.Errorf("failed to open %s", fileName)
	}

	var countries []model.Country
	for _, row := range rows {
		if len(row) != 3 {
			return nil, fmt.Errorf("missing information in country code file %s", fileName)
		}

		country := model.Country{
			Name:   row[0],
			Code:   row[1],
			Alpha3: row[2],
		}
		countries = append(countries, country)
	}

	return countries, nil
}

// loadOrgMappingsFromYaml - get country code from csv file.
func loadOrgMappingsFromYaml(filepath string) (OrgConfig, error) {
	var orgConfig OrgConfig

	bytesYaml, err := ioutil.ReadFile(filepath)
	if err != nil {
		return orgConfig, err
	}

	err = yaml.Unmarshal(bytesYaml, &orgConfig)
	if err != nil {
		return orgConfig, err
	}

	logrus.Infof("Read %d bytes remote YAML data from %s.", len(bytesYaml), filepath)

	return orgConfig, nil
}

// loadGitHubUsersFromJSON - get affiliations JSON contents
func loadGitHubUsersFromJSON(uri string) []GitHubUserFromJSON {
	var githubUsers []GitHubUserFromJSON

	var bytesJSON []byte
	if strings.HasPrefix(uri, "http://") || strings.HasPrefix(uri, "https://") {
		logrus.Infof("Downloading github_users.json file from remote...")
		response, err := http.Get(uri)
		lib.FatalOnError(err)
		defer func() { _ = response.Body.Close() }()
		bytesJSON, err = ioutil.ReadAll(response.Body)
		lib.FatalOnError(err)
	} else {
		logrus.Infof("Loading github_users.json file form local...")
		data, err := ioutil.ReadFile(uri)
		lib.FatalOnError(err)
		bytesJSON = data
	}

	logrus.Infof("Read %d bytes local JSON data from %s\n", len(bytesJSON), uri)

	err := json.Unmarshal(bytesJSON, &githubUsers)
	lib.FatalOnError(err)

	return githubUsers
}

// processUniqueIdentity - used to handle a single unique identity.
func processUniqueIdentity(
	ch chan bool, thMtx *sync.Mutex, db *gorm.DB, log *logrus.Entry,
	gc *GitHubClient, locationClient *LocationClient, employeeManager *EmployeeManager,
	githubID uint, loginSet lib.StringSet, githubID2names, githubID2emails map[uint]lib.StringSet,
	pattern2org map[*regexp.Regexp]model.Organization, domain2org map[string]model.Organization,
	githubLogin2JsonUser map[string]GitHubUserFromJSON,
) {
	if len(loginSet) == 0 {
		ch <- false
		return
	}

	// Found GitHub Logins.
	var githubLogin string
	githubUserLogins := make([]model.GitHubUserLogin, 0)
	for l := range loginSet {
		githubUserLogins = append(githubUserLogins, model.GitHubUserLogin{
			GitHubUserID: githubID,
			Login:        l,
		})
		githubLogin = l
	}

	// Found GitHub Names.
	var githubName string
	nameSet := githubID2names[githubID]
	githubUserNames := make([]model.GitHubUserName, 0)
	for n := range nameSet {
		githubUserNames = append(githubUserNames, model.GitHubUserName{
			GitHubUserID: githubID,
			Name:         n,
		})
		if len(n) > 0 {
			githubName = n
		}
	}

	// Found GitHub Emails.
	var githubEmail string
	emailSet := githubID2emails[githubID]
	githubUserEmails := make([]model.GitHubUserEmail, 0)
	for e := range emailSet {
		githubUserEmails = append(githubUserEmails, model.GitHubUserEmail{
			GitHubUserID: githubID,
			Email:        e,
		})
		if !strings.HasSuffix(e, GitHubNoReplyEmailSuffix) {
			githubEmail = e
		}
	}

	// Fetch GitHub User Profile through GitHub API.
	githubProfile, _, err := gc.GetUserByID(int64(githubID))
	if err != nil {
		log.WithError(err).Errorln("Failed to get github profile through GitHub API.")
		ch <- false
		return
	}

	// Fetch existed GitHub profile from database.
	var githubUser model.GitHubUser
	githubUser.ID = githubID
	db.Find(&githubUser)

	// Combine the login, name, and email information in GitHub Profile and devstats.
	if len(githubProfile.GetLogin()) != 0 {
		githubLogin = githubProfile.GetLogin()
		if _, ok := loginSet[githubLogin]; !ok {
			loginSet[githubLogin] = struct{}{}
			githubUserLogins = append(githubUserLogins, model.GitHubUserLogin{
				GitHubUserID: githubID,
				Login:        githubLogin,
			})
		}
	}
	if len(githubProfile.GetName()) != 0 {
		githubName = githubProfile.GetName()
		if _, ok := nameSet[githubName]; !ok {
			nameSet[githubName] = struct{}{}
			githubUserNames = append(githubUserNames, model.GitHubUserName{
				GitHubUserID: githubID,
				Name:         githubName,
			})
		}
	}
	if len(githubProfile.GetEmail()) != 0 {
		githubProfileEmail := githubProfile.GetEmail()
		if !strings.HasSuffix(githubProfileEmail, GitHubNoReplyEmailSuffix) {
			githubEmail = githubProfileEmail
		}
		if _, ok := emailSet[githubEmail]; !ok {
			emailSet[githubEmail] = struct{}{}
			githubUserEmails = append(githubUserEmails, model.GitHubUserEmail{
				GitHubUserID: githubID,
				Email:        githubEmail,
			})
		}
	}

	// Handle UUID, find or create unique identity.
	var uniqueIdentity model.UniqueIdentity
	if len(githubUser.UUID) == 0 {
		newUUID := uuid.NewString()
		githubUser.UUID = newUUID
		uniqueIdentity.UUID = newUUID
	} else {
		uniqueIdentity.UUID = githubUser.UUID
	}
	err = db.Where("uuid = ?", uniqueIdentity.UUID).FirstOrCreate(&uniqueIdentity).Error
	if err != nil {
		log.WithError(err).Errorf("Failed to find or create unique identity: %s", uniqueIdentity.UUID)
		ch <- false
		return
	}

	// Create or update GitHub Profile.
	githubCompany := githubProfile.GetCompany()
	githubLocation := githubProfile.GetLocation()
	githubBlog := githubProfile.GetBlog()
	githubBio := githubProfile.GetBio()
	githubAvatarURL := githubProfile.GetAvatarURL()

	githubUser.Login = githubLogin
	githubUser.Name = &githubName
	githubUser.Email = githubEmail
	githubUser.Following = githubProfile.GetFollowing()
	githubUser.Followers = githubProfile.GetFollowers()
	githubUser.Company = &githubCompany
	githubUser.Location = &githubLocation
	githubUser.Blog = &githubBlog
	githubUser.Bio = &githubBio
	githubUser.AvatarURL = &githubAvatarURL

	err = db.Clauses(clause.OnConflict{
		Columns: []clause.Column{
			{Name: "id"},
		},
		// Notice: Don't update the created_at field.
		DoUpdates: clause.AssignmentColumns([]string{
			"login", "email", "name", "company", "location", "followers", "following",
			"bio", "blog", "avatar_url", "updated_at",
		}),
	}).Create(&githubUser).Error
	if err != nil {
		log.WithError(err).Errorf("Failed to insert github profile (github_id=%d, github_login=%s)", githubUser.ID, githubUser.Login)
		ch <- false
		return
	}

	// Insert GitHub githubProfile logins and do nothing on conflict.
	if len(githubUserLogins) > 0 {
		db.Clauses(clause.OnConflict{
			Columns: []clause.Column{
				{Name: "github_user_id"}, {Name: "login"},
			},
			DoNothing: true,
		}).Create(&githubUserLogins)
	}

	// Insert GitHub githubProfile emails and do nothing on conflict.
	if len(githubUserEmails) > 0 {
		db.Clauses(clause.OnConflict{
			Columns: []clause.Column{
				{Name: "github_user_id"}, {Name: "email"},
			},
			DoNothing: true,
		}).Create(&githubUserEmails)
	}

	// Insert GitHub githubProfile names and do nothing on conflict.
	if len(githubUserNames) > 0 {
		db.Clauses(clause.OnConflict{
			Columns: []clause.Column{
				{Name: "github_user_id"}, {Name: "name"},
			},
			DoNothing: true,
		}).Create(&githubUserNames)
	}

	/*  Handle Unique Identity Profile  */

	// Handle Name (Only support manual and GitHub profile).
	if uniqueIdentity.NameSource != model.ManualSource && len(githubName) != 0 {
		uniqueIdentity.Name = githubName
		uniqueIdentity.NameSource = model.GitHubProfileSource
	}

	// Handle Email (Only support manual and GitHub profile).
	if uniqueIdentity.EmailSource != model.ManualSource && len(githubEmail) != 0 {
		uniqueIdentity.Email = githubEmail
		uniqueIdentity.EmailSource = model.GitHubProfileSource
	}

	// Handle Location (Only support manual and GitHub profile).
	if len(githubLocation) != 0 {
		formattedGitHubLocation, countryCode, _, err := locationClient.FormattedLocation(githubLocation)
		if err != nil {
			log.WithError(err).Errorf("Failed to format the location: %s.", githubLocation)
		}

		if uniqueIdentity.LocationSource != model.ManualSource && len(formattedGitHubLocation) != 0 {
			uniqueIdentity.Location = formattedGitHubLocation
			uniqueIdentity.LocationSource = model.GitHubProfileSource
		}
		if uniqueIdentity.CountrySource != model.ManualSource && len(countryCode) != 0 {
			uniqueIdentity.CountryCode = &countryCode
			uniqueIdentity.CountrySource = model.GitHubProfileSource
		}
	}

	// TODO: Handle Project.
	// TODO: Handle Is Bot.

	// Handle Company.
	enrollments := make([]model.Enrollment, 0)
	db.Where("uuid = ?", uniqueIdentity.UUID).Find(&enrollments)

	// First, add the affiliation information imported from json to enrollments, because this usually contains historical records.
	if jsonUser, ok := githubLogin2JsonUser[githubLogin]; ok {
		jsonSource := jsonUser.Source
		affs := jsonUser.Affiliation

		if len(uniqueIdentity.Name) == 0 && len(jsonUser.Name) != 0 {
			uniqueIdentity.Name = jsonUser.Name
			uniqueIdentity.NameSource = model.GitHubJSONSource
		}

		if uniqueIdentity.CountryCode == nil && jsonUser.CountryID != nil {
			uniqueIdentity.CountryCode = jsonUser.CountryID
			uniqueIdentity.CountrySource = model.GitHubJSONSource
		}

		// Do not process invalid affiliation information.
		isInvalidAffs := affs == "NotFound" || affs == "(Unknown)" || affs == "?" || affs == "-" || affs == ""

		if !(isInvalidAffs) {
			affsAry := strings.Split(affs, ", ")
			prevDate := model.DefaultStartDate

			for _, aff := range affsAry {
				var dtFrom, dtTo time.Time
				ary := strings.Split(aff, " < ")
				company := strings.TrimSpace(ary[0])

				if len(ary) > 1 {
					// "company < date" form
					dtFrom = prevDate
					dtTo = lib.TimeParseAny(ary[1])
				} else {
					// "company" form
					dtFrom = prevDate
					dtTo = model.DefaultEndDate
				}

				if company == "" {
					continue
				}

				thMtx.Lock()
				org := mapNameToOrg(db, pattern2org, company)
				thMtx.Unlock()

				source := model.GitHubJSONSource
				if jsonSource == "user_manual" || jsonSource == "user" {
					source = model.UserManualSource
				} else if jsonSource == "domain" {
					source = model.EmailDomainSource
				}

				if org == nil {
					continue
				}

				enrollment := model.Enrollment{
					UUID:      uniqueIdentity.UUID,
					OrgID:     org.ID,
					StartDate: dtFrom,
					EndDate:   dtTo,
					Source:    source,
				}

				alreadyIn := false
				for _, en := range enrollments {
					if en.OrgID == org.ID {
						alreadyIn = true
					}
				}

				if !alreadyIn {
					enrollments = append(enrollments, enrollment)
				}

				prevDate = dtTo
			}
		}
	}

	// Get organization through email domain.
	if len(githubUserEmails) != 0 {
		for _, email := range githubUserEmails {
			if strings.HasSuffix(email.Email, GitHubNoReplyEmailSuffix) {
				continue
			}
			for domain, org := range domain2org {
				if strings.HasSuffix(githubEmail, "@"+domain) {
					enrollments = appendEnrollment(enrollments, uniqueIdentity.UUID, org.ID, model.EmailDomainSource)
				}
			}
		}
	}

	// Get organization information through GitHub profile.
	thMtx.Lock()
	githubProfileOrg := mapNameToOrg(db, pattern2org, githubCompany)
	thMtx.Unlock()
	if githubProfileOrg != nil {
		if githubProfileOrg.Name == "ING" {
			log.Warnf("wrong org: %s %d %s", uniqueIdentity.UUID, githubProfileOrg.ID, githubCompany)
		}
		enrollments = appendEnrollment(enrollments, uniqueIdentity.UUID, githubProfileOrg.ID, model.GitHubProfileSource)
	}

	// Get organization information through Lark contact.
	isEmployee := false
	for _, login := range githubUserLogins {
		if employeeManager.IsEmployeeLogin(login.Login) {
			isEmployee = true
			break
		}
	}

	if isEmployee {
		thMtx.Lock()
		larkContactOrg := mapNameToOrg(db, pattern2org, LarkCompany)
		thMtx.Unlock()
		if larkContactOrg != nil {
			enrollments = appendEnrollment(enrollments, uniqueIdentity.UUID, larkContactOrg.ID, model.LarkContactSource)
		}
	}

	// Save enrollments.
	for _, enrollment := range enrollments {
		db.Clauses(clause.OnConflict{
			Columns: []clause.Column{
				{Name: "uuid"}, {Name: "org_id"},
			},
			DoNothing: true,
		}).Create(&enrollment)
	}

	// Save Profile.
	err = db.Updates(&uniqueIdentity).Error
	if err != nil {
		log.WithError(err).Errorf("Failed to save unique identity: %s", uniqueIdentity.UUID)
		ch <- false
		return
	}

	ch <- true
}

func appendEnrollment(
	enrollments []model.Enrollment, uuid string, newOrgID uint,
	source model.ProfileSource,
) []model.Enrollment {
	if len(enrollments) == 0 {
		enrollment := model.Enrollment{
			OrgID:     newOrgID,
			UUID:      uuid,
			StartDate: model.DefaultStartDate,
			EndDate:   model.DefaultEndDate,
			Source:    source,
		}
		enrollments = append(enrollments, enrollment)
	} else {
		sort.Slice(enrollments, func(i, j int) bool {
			return enrollments[i].StartDate.Before(enrollments[j].StartDate) && enrollments[i].EndDate.Before(enrollments[j].EndDate)
		})

		lastIndex := len(enrollments) - 1
		alreadyIn := false
		for _, enrollment := range enrollments {
			if enrollment.OrgID == newOrgID {
				alreadyIn = true
				break
			}
		}

		if alreadyIn {
			return enrollments
		}

		now := time.Now()
		enrollments[lastIndex].EndDate = now
		enrollment := model.Enrollment{
			UUID:      uuid,
			OrgID:     newOrgID,
			StartDate: now,
			EndDate:   model.DefaultEndDate,
			Source:    source,
		}
		enrollments = append(enrollments, enrollment)
	}

	return enrollments
}

func mapNameToOrg(db *gorm.DB, pattern2org map[*regexp.Regexp]model.Organization, orgName string) *model.Organization {
	orgName = strings.TrimSpace(orgName)

	// orgName requires at least two characters.
	if len(orgName) < 2 {
		return nil
	}

	for reg, org := range pattern2org {
		if reg.MatchString(orgName) {
			return &org
		}
	}

	// If not match, try to create a new organization.
	orgType := model.OrgTypeCompany
	if isEducationOrgName(orgName) {
		orgType = model.OrgTypeEducation
	}
	newOrg := model.Organization{
		Name: orgName,
		Type: orgType,
	}
	db.Where("name = ?", orgName).FirstOrCreate(&newOrg)

	if newOrg.ID == 0 || newOrg.Invalid {
		return nil
	}

	// Add name match pattern.
	pattern := fmt.Sprintf("^\\s*%s\\s*$", escapeRegexStr(orgName))
	db.Clauses(clause.OnConflict{
		Columns: []clause.Column{
			{Name: "org_id"},
			{Name: "pattern"},
		},
		DoNothing: true,
	}).Create(&model.OrgPattern{
		OrgID:   newOrg.ID,
		Pattern: pattern,
	})
	reg := regexp.MustCompile("(?i)" + pattern)
	pattern2org[reg] = newOrg

	return &newOrg
}

func isEducationOrgName(orgName string) bool {
	orgName = strings.ToLower(orgName)
	return strings.HasPrefix(orgName, "university") ||
		strings.HasPrefix(orgName, "college") ||
		strings.HasPrefix(orgName, "大学") ||
		strings.HasPrefix(orgName, "Universidad") ||
		strings.HasPrefix(orgName, "Universitat") ||
		strings.HasPrefix(orgName, "université") ||
		strings.HasPrefix(orgName, "universitas") ||
		strings.HasPrefix(orgName, "universidade") ||
		strings.HasPrefix(orgName, "universitetet") ||
		strings.HasPrefix(orgName, "universitetet") ||
		strings.HasSuffix(orgName, "university") ||
		strings.HasSuffix(orgName, "college") ||
		strings.HasSuffix(orgName, "学院") ||
		strings.HasSuffix(orgName, "Universidad")
}

// escapeRegexStr - escape regular expression symbols in strings.
func escapeRegexStr(str string) string {
	str = strings.TrimSpace(str)
	// Notice: \ must be in the first place.
	escapeArr := []string{"\\", "[", "]", "^", "$", ".", "|", "?", "*", "+", "(", ")"}
	for _, symbol := range escapeArr {
		str = strings.ReplaceAll(str, symbol, "\\"+symbol)
	}
	return str
}

type EnrollmentWithOrg struct {
	OrgName   string
	StartDate time.Time
	EndDate   time.Time
}

func OutputGitHubUserToJSON(log *logrus.Entry, ctx *Ctx, db *gorm.DB) {
	uniqueIdentities := make([]model.UniqueIdentity, 0)
	db.Preload("GitHubUsers").Preload("Country").Find(&uniqueIdentities)

	githubUsersToJSON := make([]GitHubUserFromJSON, 0)
	nUnique := len(uniqueIdentities)
	i := 0
	for _, uniqueIdentity := range uniqueIdentities {
		if i%100 == 0 || i == nUnique-1 {
			log.Infof("Processing %d/%d unique identities.", i+1, nUnique)
		}
		i++

		u := uniqueIdentity.UUID

		enrollments := make([]EnrollmentWithOrg, 0)
		db.Raw(
			"select o.name as org_name, e.start_date as start_date, e.end_date as end_date from enrollments e "+
				"left join organizations o on e.org_id = o.id "+
				"where uuid = ? and e.invalid = ? and o.invalid = ? "+
				"order by e.start_date, e.end_date",
			u, false, false,
		).Scan(&enrollments)

		githubUsers := make([]model.GitHubUser, 0)
		db.Preload("Emails").Preload("Logins").Preload("Names").
			Where("uuid = ?", u).Find(&githubUsers)

		for _, user := range githubUsers {
			for _, login := range user.Logins {
				for _, email := range user.Emails {
					var githubUser GitHubUserFromJSON

					githubUser.Login = login.Login
					githubUser.Email = email.Email
					githubUser.Name = uniqueIdentity.Name
					githubUser.Sex = &uniqueIdentity.Gender
					githubUser.SexProb = &uniqueIdentity.GenderAcc
					githubUser.CountryID = uniqueIdentity.CountryCode
					githubUser.Source = "user_manual"

					if uniqueIdentity.IsBot {
						githubUser.Affiliation = "(Robots)"
					} else {
						githubUser.Affiliation = getAffStr(enrollments)
					}

					githubUsersToJSON = append(githubUsersToJSON, githubUser)
				}
			}
		}
	}

	var bf bytes.Buffer
	encoder := json.NewEncoder(&bf)
	encoder.SetIndent("", "\t")
	encoder.SetEscapeHTML(false)
	err := encoder.Encode(&githubUsersToJSON)
	if err != nil {
		log.WithError(err).Errorf("Failed to encode github user json.")
		return
	}

	// Output to json file.
	filename := ctx.GitHubUsersJSONOutputPath
	err = ioutil.WriteFile(filename, bf.Bytes(), 0666)
	if err != nil {
		log.WithError(err).Errorf("Failed to output github user json.")
		return
	}
	log.Infof("Output %s successfully.", filename)

	if !ctx.S3UploadGitHubUsersJSON {
		return
	}

	// Upload file to S3.
	sess := session.Must(session.NewSession(&aws.Config{
		Region: aws.String(ctx.AwsDefaultRegion),
	}))
	envCredentials := credentials.NewEnvCredentials()
	s3Svc := s3.New(sess, &aws.Config{
		Credentials: envCredentials,
	})

	s3bucket := aws.String(ctx.S3GitHubUsersJSONBucket)
	s3key := aws.String(ctx.S3GitHubUsersJSONBucketKey)
	background := context.Background()

	_, err = s3Svc.PutObjectWithContext(background, &s3.PutObjectInput{
		Bucket: s3bucket,
		Key:    s3key,
		Body:   bytes.NewReader(bf.Bytes()),
	})
	if err != nil {
		if aerr, ok := err.(awserr.Error); ok && aerr.Code() == request.CanceledErrorCode {
			log.Errorf("upload canceled due to timeout, %v.", err)
		} else {
			log.Errorf("failed to upload object, %v.", err)
		}
		lib.FatalOnError(err)
	}

	log.Infof("successfully uploaded file to %s/%s", *s3bucket, *s3key)
}

// getAffStr - generate affiliation information string based on enrollments.
func getAffStr(enrollments []EnrollmentWithOrg) string {
	if len(enrollments) == 0 {
		return ""
	}

	if len(enrollments) == 1 {
		return enrollments[0].OrgName
	}

	affs := ""
	for i, enrollment := range enrollments {
		if i == len(enrollments)-1 {
			affs = affs + enrollment.OrgName
		} else {
			affs = affs + enrollment.OrgName + " < " + enrollment.EndDate.Format("2006-01-02") + ", "
		}
	}

	return affs
}
