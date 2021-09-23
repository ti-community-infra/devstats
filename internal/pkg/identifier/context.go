package identifier

import (
	"os"
	"strconv"

	"github.com/ti-community-infra/devstats/internal/pkg/lib"
)

type Ctx struct {
	IDDbDialect string // From ID_DB_DIALECT, default "mysql"
	IDDbHost    string // From ID_DB_HOST, default "localhost"
	IDDbPort    int    // From ID_DB_PORT, default "3306"
	IDDbName    string // From ID_DB_NAME, default "sortinghat"
	IDDbUser    string // From ID_DB_USER, default "root"
	IDDbPass    string // From ID_DB_PASS, default "password"
	IDDbSSL     string // From ID_DB_SSL, default "disable"

	SkipBots                 bool // From SKIP_BOTS, default false
	SkipAutoImportProfile    bool // From SKIP_AUTO_IMPORT_PROFILE, default false.
	SkipOutputGitHubUserJSON bool // From SKIP_OUTPUT_GITHUB_USER_JSON, default false.

	GitHubUsersJSONSourcePath string // From ID_GITHUB_USERS_JSON_SOURCE_PATH
	GitHubUsersJSONOutputPath string // From ID_GITHUB_USERS_JSON_OUTPUT_PATH
	CountryCodesFilePath      string // From ID_COUNTRY_CODES_FILE_PATH, default "data/countries.csv"
	CacheFilePath             string // From ID_CACHE_FILE_PATH, default "data/dump.out"
	OrganizationsFilePath     string // From ID_ORGANIZATION_CONFIG_YAML, default "configs/shared/organizations.yaml"

	GoogleMapAPIKey string // From GOOGLE_MAP_API_KEY

	LarkAPIBaseURL string // From LARK_API_BASE_URL
	LarkAppID      string // From LARK_APP_ID
	LarkAppSecret  string // From LARK_APP_SECRET

	S3UploadGitHubUsersJSON    bool   // From S3_UPLOAD_GITHUB_USERS_JSON
	S3GitHubUsersJSONBucket    string // From S3_GITHUB_USERS_JSON_BUCKET
	S3GitHubUsersJSONBucketKey string // From S3_GITHUB_USERS_JSON_BUCKET_KEY
	AwsAccessKeyID             string // From AWS_ACCESS_KEY_ID
	AwsSecretAccessKey         string // From AWS_SECRET_ACCESS_KEY
	AwsDefaultRegion           string // From AWS_DEFAULT_REGION

	DevstatsAPIBaseURL string // From DEVSTATS_API_BASE_URL

	lib.Ctx
}

func (c *Ctx) Init() error {
	c.Ctx.Init()

	// Identity database.
	c.IDDbDialect = "mysql"
	if os.Getenv("ID_DB_DIALECT") != "" {
		c.IDDbDialect = os.Getenv("ID_DB_DIALECT")
	}
	c.IDDbHost = "localhost"
	if os.Getenv("ID_DB_HOST") != "" {
		c.IDDbHost = os.Getenv("ID_DB_HOST")
	}
	c.IDDbPort = 3306
	sDBPort := os.Getenv("ID_DB_PORT")
	if sDBPort != "" {
		var err error
		c.IDDbPort, err = strconv.Atoi(sDBPort)
		if err != nil {
			return err
		}
	}
	c.IDDbName = "sortinghat"
	if os.Getenv("ID_DB_NAME") != "" {
		c.IDDbName = os.Getenv("ID_DB_NAME")
	}
	c.IDDbUser = "root"
	if os.Getenv("ID_DB_USER") != "" {
		c.IDDbUser = os.Getenv("ID_DB_USER")
	}
	c.IDDbPass = "password"
	if os.Getenv("ID_DB_PASS") != "" {
		c.IDDbPass = os.Getenv("ID_DB_PASS")
	}
	c.IDDbSSL = "disable"
	if os.Getenv("ID_DB_SSL") != "" {
		c.IDDbSSL = os.Getenv("ID_DB_SSL")
	}

	// Country Codes.
	c.CountryCodesFilePath = "configs/shared/countries.csv"
	if os.Getenv("ID_COUNTRY_CODES_FILE_PATH") != "" {
		c.CountryCodesFilePath = os.Getenv("ID_COUNTRY_CODES_FILE_PATH")
	}

	// Organization
	c.OrganizationsFilePath = os.Getenv("ID_ORGANIZATION_CONFIG_YAML")
	if c.OrganizationsFilePath == "" {
		c.OrganizationsFilePath = "configs/shared/organizations.yaml"
	}

	c.GitHubUsersJSONOutputPath = os.Getenv("ID_GITHUB_USERS_JSON_OUTPUT_PATH")
	if c.GitHubUsersJSONOutputPath == "" {
		c.GitHubUsersJSONOutputPath = "configs/shared/github_users.json"
	}

	c.GitHubUsersJSONSourcePath = os.Getenv("ID_GITHUB_USERS_JSON_SOURCE_PATH")
	if c.GitHubUsersJSONSourcePath == "" {
		c.GitHubUsersJSONSourcePath = "https://media.githubusercontent.com/media/cncf/gitdm/master/src/github_users.json"
	}

	// Cache
	c.CacheFilePath = "dump.out"
	if os.Getenv("ID_CACHE_FILE_PATH") != "" {
		c.CacheFilePath = os.Getenv("ID_CACHE_FILE_PATH")
	}

	// Skip
	c.SkipBots = false
	if os.Getenv("SKIP_BOTS") != "" {
		c.SkipBots = true
	}

	c.SkipAutoImportProfile = false
	if os.Getenv("SKIP_AUTO_IMPORT_PROFILE") != "" {
		c.SkipAutoImportProfile = true
	}

	c.SkipOutputGitHubUserJSON = false
	if os.Getenv("SKIP_OUTPUT_GITHUB_USER_JSON") != "" {
		c.SkipOutputGitHubUserJSON = true
	}

	// Google Maps
	c.GoogleMapAPIKey = os.Getenv("GOOGLE_MAP_API_KEY")

	// Lark
	c.LarkAPIBaseURL = os.Getenv("LARK_API_BASE_URL")
	if len(c.LarkAPIBaseURL) == 0 {
		c.LarkAPIBaseURL = "https://open.feishu.cn/open-apis"
	}
	c.LarkAppID = os.Getenv("LARK_APP_ID")
	c.LarkAppSecret = os.Getenv("LARK_APP_SECRET")

	// S3
	c.S3UploadGitHubUsersJSON = false
	if os.Getenv("S3_UPLOAD_GITHUB_USERS_JSON") != "" {
		c.S3UploadGitHubUsersJSON = true
	}

	c.S3GitHubUsersJSONBucket = os.Getenv("S3_GITHUB_USERS_JSON_BUCKET")
	c.S3GitHubUsersJSONBucketKey = os.Getenv("S3_GITHUB_USERS_JSON_BUCKET_KEY")
	c.AwsAccessKeyID = os.Getenv("AWS_ACCESS_KEY_ID")
	c.AwsSecretAccessKey = os.Getenv("AWS_SECRET_ACCESS_KEY")
	c.AwsDefaultRegion = os.Getenv("AWS_DEFAULT_REGION")

	c.DevstatsAPIBaseURL = os.Getenv("DEVSTATS_API_BASE_URL")

	return nil
}
