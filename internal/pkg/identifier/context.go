package identifier

import (
	"os"
	"strconv"

	"github.com/ti-community-infra/devstats/internal/pkg/lib"
)

type Ctx struct {
	IdDbDialect string // From ID_DB_DIALECT, default "mysql"
	IdDbHost    string // From ID_DB_HOST, default "localhost"
	IdDbPort    int    // From ID_DB_PORT, default "3306"
	IdDbName    string // From ID_DB_NAME, default "sortinghat"
	IdDbUser    string // From ID_DB_USER, default "root"
	IdDbPass    string // From ID_DB_PASS, default "password"
	IdDbSSL     string // From ID_DB_SSL, default "disable"

	SkipBots                 bool // From SKIP_BOTS, default false
	SkipAutoImportProfile    bool // From SKIP_AUTO_IMPORT_PROFILE, default false.
	SkipOutputGitHubUserJson bool // From SKIP_OUTPUT_GITHUB_USER_JSON, default false.

	GitHubUsersJsonOutputPath string // From ID_GITHUB_USERS_JSON_OUTPUT_PATH
	CountryCodesFilePath      string // From ID_COUNTRY_CODES_FILE_PATH, default "data/countries.csv"
	CacheFilePath             string // From ID_CACHE_FILE_PATH, default "data/dump.out"
	OrganizationsFilePath     string // From ID_ORGANIZATION_CONFIG_YAML, default "data/dump.out"

	GoogleMapAPIKey string // From GOOGLE_MAP_API_KEY

	LarkAPIBaseUrl string // From LARK_API_BASE_URL
	LarkAppId      string // From LARK_APP_ID
	LarkAppSecret  string // From LARK_APP_SECRET

	S3UploadGitHubUsersJson    bool   // From S3_UPLOAD_GITHUB_USERS_JSON
	S3GitHubUsersJsonBucket    string // From S3_GITHUB_USERS_JSON_BUCKET
	S3GitHubUsersJsonBucketKey string // From S3_GITHUB_USERS_JSON_BUCKET_KEY
	AwsAccessKeyId             string // From AWS_ACCESS_KEY_ID
	AwsSecretAccessKey         string // From AWS_SECRET_ACCESS_KEY
	AwsDefaultRegion           string // From AWS_DEFAULT_REGION

	lib.Ctx
}

func (c *Ctx) Init() error {
	c.Ctx.Init()

	// Identity database.
	c.IdDbDialect = "mysql"
	if os.Getenv("ID_DB_DIALECT") != "" {
		c.IdDbDialect = os.Getenv("ID_DB_DIALECT")
	}
	c.IdDbHost = "localhost"
	if os.Getenv("ID_DB_HOST") != "" {
		c.IdDbHost = os.Getenv("ID_DB_HOST")
	}
	c.IdDbPort = 3306
	sDBPort := os.Getenv("ID_DB_PORT")
	if sDBPort != "" {
		var err error
		c.IdDbPort, err = strconv.Atoi(sDBPort)
		if err != nil {
			return err
		}
	}
	c.IdDbName = "sortinghat"
	if os.Getenv("ID_DB_NAME") != "" {
		c.IdDbName = os.Getenv("ID_DB_NAME")
	}
	c.IdDbUser = "root"
	if os.Getenv("ID_DB_USER") != "" {
		c.IdDbUser = os.Getenv("ID_DB_USER")
	}
	c.IdDbPass = "password"
	if os.Getenv("ID_DB_PASS") != "" {
		c.IdDbPass = os.Getenv("ID_DB_PASS")
	}
	c.IdDbSSL = "disable"
	if os.Getenv("ID_DB_SSL") != "" {
		c.IdDbSSL = os.Getenv("ID_DB_SSL")
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

	c.GitHubUsersJsonOutputPath = os.Getenv("ID_GITHUB_USERS_JSON_OUTPUT_PATH")
	if c.GitHubUsersJsonOutputPath == "" {
		c.GitHubUsersJsonOutputPath = "configs/shared/github_users.json"
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

	c.SkipOutputGitHubUserJson = false
	if os.Getenv("SKIP_OUTPUT_GITHUB_USER_JSON") != "" {
		c.SkipOutputGitHubUserJson = true
	}

	// Google Maps
	c.GoogleMapAPIKey = os.Getenv("GOOGLE_MAP_API_KEY")

	// Lark
	c.LarkAPIBaseUrl = os.Getenv("LARK_API_BASE_URL")
	if len(c.LarkAPIBaseUrl) == 0 {
		c.LarkAPIBaseUrl = "https://open.feishu.cn/open-apis"
	}
	c.LarkAppId = os.Getenv("LARK_APP_ID")
	c.LarkAppSecret = os.Getenv("LARK_APP_SECRET")

	// S3
	c.S3UploadGitHubUsersJson = false
	if os.Getenv("S3_UPLOAD_GITHUB_USERS_JSON") != "" {
		c.S3UploadGitHubUsersJson = true
	}

	c.S3GitHubUsersJsonBucket = os.Getenv("S3_GITHUB_USERS_JSON_BUCKET")
	c.S3GitHubUsersJsonBucketKey = os.Getenv("S3_GITHUB_USERS_JSON_BUCKET_KEY")
	c.AwsAccessKeyId = os.Getenv("AWS_ACCESS_KEY_ID")
	c.AwsSecretAccessKey = os.Getenv("AWS_SECRET_ACCESS_KEY")
	c.AwsDefaultRegion = os.Getenv("AWS_DEFAULT_REGION")

	return nil
}
