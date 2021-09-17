package identifier

import (
	"testing"
	"time"

	"github.com/ti-community-infra/devstats/internal/pkg/storage/model"
)

func TestAppendEnrollment(t *testing.T) {
	var testcases = []struct {
		name        string
		enrollments []model.Enrollment
		uuid        string
		orgID       uint
		source      model.ProfileSource

		expectEnrollments []model.Enrollment
	}{
		{
			name:        "the original enrollments slice is empty",
			enrollments: []model.Enrollment{},
			uuid:        "uuid",
			orgID:       1,
			source:      model.GitHubProfileSource,

			expectEnrollments: []model.Enrollment{
				{
					UUID:      "uuid",
					OrgID:     1,
					StartDate: model.DefaultStartDate,
					EndDate:   model.DefaultEndDate,
					Source:    model.GitHubProfileSource,
				},
			},
		},
		{
			name: "the original enrollments slice is not empty",
			enrollments: []model.Enrollment{
				{
					UUID:      "uuid",
					OrgID:     1,
					StartDate: model.DefaultStartDate,
					EndDate:   model.DefaultEndDate,
					Source:    model.GitHubProfileSource,
				},
			},
			uuid:   "uuid",
			orgID:  2,
			source: model.GitHubProfileSource,

			expectEnrollments: []model.Enrollment{
				{
					UUID:      "uuid",
					OrgID:     1,
					StartDate: model.DefaultStartDate,
					EndDate:   time.Now(),
					Source:    model.GitHubProfileSource,
				},
				{
					UUID:      "uuid",
					OrgID:     2,
					StartDate: time.Now(),
					EndDate:   model.DefaultEndDate,
					Source:    model.GitHubProfileSource,
				},
			},
		},
		{
			name: "the original enrollments slice is not empty",
			enrollments: []model.Enrollment{
				{
					UUID:      "uuid",
					OrgID:     1,
					StartDate: model.DefaultStartDate,
					EndDate:   time.Date(2018, 9, 1, 0, 0, 0, 0, time.UTC),
					Source:    model.GitHubProfileSource,
				},
				{
					UUID:      "uuid",
					OrgID:     2,
					StartDate: time.Date(2019, 9, 7, 0, 0, 0, 0, time.UTC),
					EndDate:   model.DefaultEndDate,
					Source:    model.GitHubProfileSource,
				},
				{
					UUID:      "uuid",
					OrgID:     3,
					StartDate: time.Date(2018, 9, 1, 0, 0, 0, 0, time.UTC),
					EndDate:   time.Date(2019, 9, 7, 0, 0, 0, 0, time.UTC),
					Source:    model.GitHubProfileSource,
				},
			},
			uuid:   "uuid",
			orgID:  4,
			source: model.GitHubProfileSource,

			expectEnrollments: []model.Enrollment{
				{
					UUID:      "uuid",
					OrgID:     1,
					StartDate: model.DefaultStartDate,
					EndDate:   time.Date(2018, 9, 1, 0, 0, 0, 0, time.UTC),
					Source:    model.GitHubProfileSource,
				},
				{
					UUID:      "uuid",
					OrgID:     3,
					StartDate: time.Date(2018, 9, 1, 0, 0, 0, 0, time.UTC),
					EndDate:   time.Date(2019, 9, 7, 0, 0, 0, 0, time.UTC),
					Source:    model.GitHubProfileSource,
				},
				{
					UUID:      "uuid",
					OrgID:     2,
					StartDate: time.Date(2019, 9, 7, 0, 0, 0, 0, time.UTC),
					EndDate:   time.Now(),
					Source:    model.GitHubProfileSource,
				},
				{
					UUID:      "uuid",
					OrgID:     4,
					StartDate: time.Now(),
					EndDate:   model.DefaultEndDate,
					Source:    model.GitHubProfileSource,
				},
			},
		},
	}

	for _, testcase := range testcases {
		tc := testcase
		t.Run(tc.name, func(t *testing.T) {
			gotEnrollments := appendEnrollment(tc.enrollments, tc.uuid, tc.orgID, tc.source)

			if len(gotEnrollments) != len(tc.expectEnrollments) {
				t.Errorf("Expect enrollments len: %d, but go %d", len(tc.expectEnrollments), len(gotEnrollments))
			}

			for i, expectEnrollment := range tc.expectEnrollments {
				gotEnrollment := gotEnrollments[i]

				if gotEnrollment.UUID != expectEnrollment.UUID ||
					gotEnrollment.OrgID != expectEnrollment.OrgID ||
					gotEnrollment.Source != expectEnrollment.Source ||
					gotEnrollment.StartDate.Sub(expectEnrollment.StartDate) > time.Second*3 ||
					gotEnrollment.EndDate.Sub(expectEnrollment.EndDate) > time.Second*3 {
					t.Errorf("Expect enrollment: %v, got %v", expectEnrollment, gotEnrollment)
				}
			}
		})
	}
}
