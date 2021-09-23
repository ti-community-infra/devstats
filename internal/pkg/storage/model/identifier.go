package model

import (
	"time"

	"gorm.io/gorm"
)

type OrganizationType string

const (
	OrgTypeCompany    OrganizationType = "company"
	OrgTypeEducation  OrganizationType = "education"
	OrgTypeOpenSource OrganizationType = "open_source"
	OrgTypeIndividual OrganizationType = "individual"
)

type TeamLevel string

const (
	TeamMaintainer TeamLevel = "maintainer"
	TeamCommitter  TeamLevel = "committer"
	TeamReviewer   TeamLevel = "reviewer"
)

type ProfileSource string

const (
	// GitHubProfileSource get the profile of a GitHub user through the GitHub API.
	GitHubProfileSource ProfileSource = "github_profile"
	// EmailDomainSource means information is inferred from the domain name part in the email.
	EmailDomainSource ProfileSource = "email_domain"
	// GitHubJSONSource means information is imported from GitHub user json file, which provided by cncf/gitdm.
	GitHubJSONSource ProfileSource = "github_json"
	// LarkContactSource means determine whether is an employee of the specified company according to whether GitHub login is in the Lark contact.
	LarkContactSource ProfileSource = "lark_contact"
	// ManualSource means information is provided through manual verification.
	ManualSource ProfileSource = "manual"
	// UserManualSource means information is provided through manual verification by user.
	UserManualSource ProfileSource = "user_manual"
)

type Country struct {
	Code   string `gorm:"primaryKey;type:char(2)"`
	Name   string `gorm:"type:varchar(128)"`
	Alpha3 string `gorm:"type:char(3);uniqueIndex:uniq_country_alpha3,sort:asc"`
}

func (Country) TableName() string {
	return "countries"
}

type Project struct {
	gorm.Model

	DisplayName string `gorm:"type:varchar(128);not null;"`
	Name        string `gorm:"type:varchar(128);uniqueIndex;not null;"`

	Teams []Team `gorm:"foreignKey:project_id"`
}

func (Project) TableName() string {
	return "projects"
}

type Team struct {
	gorm.Model

	Name         string `gorm:"uniqueIndex"`
	Description  string
	ProjectID    uint             `gorm:"project_id"`
	Members      []UniqueIdentity `gorm:"many2many:team_members;foreignKey:ID;joinForeignKey:team_id;References:UUID;JoinReferences:uuid"`
	Repositories []Repository     `gorm:"many2many:team_repositories;foreignKey:ID;joinForeignKey:team_id;References:ID;JoinReferences:repo_id"`
	Project      Project          `gorm:"foreignKey:project_id"`
}

func (Team) TableName() string {
	return "teams"
}

type TeamMember struct {
	TeamID uint   `gorm:"primaryKey;"`
	UUID   string `gorm:"primaryKey;type:varchar(128)"`
	Level  TeamLevel

	DupGitHubID    uint   `gorm:"column:dup_github_id;"`
	DupGitHubLogin string `gorm:"column:dup_github_login;type:varchar(128);not null"`
	DupEmail       string `gorm:"type:varchar(255);"`

	Team           Team           `gorm:"foreignKey:team_id"`
	UniqueIdentity UniqueIdentity `gorm:"foreignKey:uuid"`

	JoinDate       time.Time
	LastUpdateDate time.Time
}

func (TeamMember) TableName() string {
	return "team_members"
}

type Repository struct {
	gorm.Model

	Name      string
	Owner     string
	ProjectID uint
}

func (Repository) TableName() string {
	return "repositories"
}

type TeamMemberChangeLog struct {
	gorm.Model

	TeamID         uint   `gorm:"uniqueIndex:uniq_team_member_change_log;"`
	UUID           string `gorm:"type:varchar(128);uniqueIndex:uniq_team_member_change_log;"`
	CommitSHA      string `gorm:"uniqueIndex:uniq_team_member_change_log;"`
	DupGitHubID    uint   `gorm:"column:dup_github_id;"`
	DupGitHubLogin string `gorm:"column:dup_github_login;type:varchar(128);not null"`

	CommitMessage string
	LevelFrom     *TeamLevel
	LevelTo       *TeamLevel
	ChangedAt     time.Time
}

type UniqueIdentity struct {
	UUID           string        `gorm:"primaryKey;type:varchar(128);"`
	Name           string        `gorm:"type:varchar(128)"`
	NameSource     ProfileSource `gorm:"type:varchar(32)"`
	Email          string        `gorm:"type:varchar(128)"`
	EmailSource    ProfileSource `gorm:"type:varchar(32)"`
	Gender         string        `gorm:"type:varchar(10)"`
	GenderAcc      float64       `gorm:"type:float"`
	GenderSource   ProfileSource `gorm:"type:varchar(32)"`
	Location       string        `gorm:"type:varchar(255)"`
	LocationSource ProfileSource `gorm:"type:varchar(32)"`
	Country        Country       `gorm:"foreignKey:country_code"`
	CountryCode    *string       `gorm:"type:char(2)"`
	CountrySource  ProfileSource `gorm:"type:varchar(32)"`
	IsBot          bool          `gorm:"default:0"`

	// One person can have multiple GitHub accounts.
	GitHubUsers []GitHubUser `gorm:"foreignKey:uuid"`

	// One person can belong to multiple organizations.
	Organizations []Organization `gorm:"many2many:enrollments;foreignKey:UUID;joinForeignKey:uuid;References:ID;JoinReferences:org_id"`

	// One person can participate in multiple projects.
	Projects []Project `gorm:"many2many:project_participants;foreignKey:UUID;joinForeignKey:uuid;References:ID;JoinReferences:project_id"`
}

func (UniqueIdentity) TableName() string {
	return "unique_identities"
}

type Organization struct {
	gorm.Model

	Name      string           `gorm:"type:varchar(255);not null"`
	Fullname  string           `gorm:"type:varchar(255);"`
	Type      OrganizationType `gorm:"type:varchar(32);default:'company';not null"`
	Website   string           `gorm:"type:varchar(255);"`
	IsPartner bool             `gorm:"default: 0"`

	// Invalid - enrollment associated with invalid org will not be displayed and exported,
	// it can be used to prevent invalid organizations from being added repeatedly.
	Invalid bool `gorm:"default:0"`

	// Notice: An organization may have multiple domain names, the email domain can be used to
	// infer that the contributor belongs to an organization.
	Domains  []OrgDomain  `gorm:"foreignKey:org_id"`
	Patterns []OrgPattern `gorm:"foreignKey:org_id"`
}

func (Organization) TableName() string {
	return "organizations"
}

type OrgPattern struct {
	gorm.Model

	Pattern string `gorm:"type:varchar(512);not null;uniqueIndex:uniq_org_pattern"`
	OrgID   uint   `gorm:"uniqueIndex:uniq_org_pattern"`
}

func (OrgPattern) TableName() string {
	return "organization_patterns"
}

type OrgDomain struct {
	gorm.Model

	Name  string `yaml:"name" gorm:"type:varchar(255);not null;uniqueIndex:uniq_org_org_domain_name"`
	IsTop bool   `yaml:"is_top"`

	// Common indicates whether the domain name is a public email domain name, such as `gmail.com`.
	Common bool
	OrgID  uint `gorm:"uniqueIndex:uniq_org_org_domain_name"`
}

func (OrgDomain) TableName() string {
	return "organization_domains"
}

type Enrollment struct {
	OrgID     uint      `gorm:"primaryKey;uniqueIndex:uniq_org_enrollment;"`
	UUID      string    `gorm:"primaryKey;uniqueIndex:uniq_org_enrollment;"`
	StartDate time.Time `gorm:"uniqueIndex:uniq_org_enrollment;"`
	EndDate   time.Time `gorm:"uniqueIndex:uniq_org_enrollment;"`
	Invalid   bool      `gorm:"default:0"`
	Source    ProfileSource
}

func (Enrollment) TableName() string {
	return "enrollments"
}

type GitHubUser struct {
	gorm.Model

	Login     string  `gorm:"type:varchar(128);not null"`
	Email     string  `gorm:"type:varchar(255);not null"`
	Name      *string `gorm:"type:varchar(128);"`
	Location  *string `gorm:"type:varchar(255);"`
	Company   *string `gorm:"type:varchar(255);"`
	Blog      *string `gorm:"type:varchar(255);"`
	Bio       *string `gorm:"type:varchar(512);"`
	Following int     `gorm:"type:int;default:0"`
	Followers int     `gorm:"type:int;default:0"`
	AvatarURL *string `gorm:"type:varchar(255);"`
	UUID      string  `gorm:"type:varchar(128);"`

	Emails []GitHubUserEmail `gorm:"foreignKey:github_user_id"`
	Logins []GitHubUserLogin `gorm:"foreignKey:github_user_id"`
	Names  []GitHubUserName  `gorm:"foreignKey:github_user_id"`
}

func (GitHubUser) TableName() string {
	return "github_users"
}

type GitHubUserEmail struct {
	gorm.Model

	GitHubUserID uint   `gorm:"column:github_user_id;not null;uniqueIndex:uniq_github_user_email"`
	Email        string `gorm:"type:varchar(255);not null;uniqueIndex:uniq_github_user_email"`
}

func (GitHubUserEmail) TableName() string {
	return "github_user_emails"
}

type GitHubUserLogin struct {
	gorm.Model

	GitHubUserID uint   `gorm:"column:github_user_id;not null;uniqueIndex:uniq_github_user_login"`
	Login        string `gorm:"type:varchar(128);not null;uniqueIndex:uniq_github_user_login"`
}

func (GitHubUserLogin) TableName() string {
	return "github_user_logins"
}

type GitHubUserName struct {
	gorm.Model

	GitHubUserID uint   `gorm:"column:github_user_id;not null;uniqueIndex:uniq_github_user_name"`
	Name         string `gorm:"type:varchar(128);not null;uniqueIndex:uniq_github_user_name"`
}

func (GitHubUserName) TableName() string {
	return "github_user_names"
}
