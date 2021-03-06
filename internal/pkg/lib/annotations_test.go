package lib

import (
	"reflect"
	"testing"
	"time"

	"github.com/ti-community-infra/devstats/internal/pkg/testlib"
)

func TestGetFakeAnnotations(t *testing.T) {
	// Example data
	ft := testlib.YMDHMS
	startDate := []time.Time{ft(2014), ft(2015), ft(2015), ft(2012)}
	joinDate := []time.Time{ft(2015), ft(2015), ft(2014), ft(2013)}

	// Test cases
	var testCases = []struct {
		startDate           time.Time
		joinDate            time.Time
		expectedAnnotations Annotations
	}{
		{
			startDate: startDate[0],
			joinDate:  joinDate[0],
			expectedAnnotations: Annotations{
				Annotations: []Annotation{
					{
						Name:        "Project start",
						Description: ToYMDDate(startDate[0]) + " - project starts",
						Date:        startDate[0],
					},
					{
						Name:        "First CNCF project join date",
						Description: ToYMDDate(joinDate[0]),
						Date:        joinDate[0],
					},
				},
			},
		},
		{
			startDate: startDate[1],
			joinDate:  joinDate[1],
			expectedAnnotations: Annotations{
				Annotations: []Annotation{},
			},
		},
		{
			startDate: startDate[2],
			joinDate:  joinDate[2],
			expectedAnnotations: Annotations{
				Annotations: []Annotation{},
			},
		},
		{
			startDate: startDate[3],
			joinDate:  joinDate[3],
			expectedAnnotations: Annotations{
				Annotations: []Annotation{},
			},
		},
		{
			startDate: startDate[0],
			joinDate:  joinDate[3],
			expectedAnnotations: Annotations{
				Annotations: []Annotation{},
			},
		},
		{
			startDate: startDate[3],
			joinDate:  joinDate[0],
			expectedAnnotations: Annotations{
				Annotations: []Annotation{},
			},
		},
	}
	// Execute testlib cases
	for index, test := range testCases {
		expected := test.expectedAnnotations
		got := GetFakeAnnotations(test.startDate, test.joinDate)
		if (len(expected.Annotations) > 0 || len(got.Annotations) > 0) && !reflect.DeepEqual(expected.Annotations, got.Annotations) {
			t.Errorf(
				"testlib number %d, expected:\n%+v\n%+v\n got, start date: %s, join date: %s",
				index+1,
				expected,
				got,
				ToYMDDate(test.startDate),
				ToYMDDate(test.joinDate),
			)
		}
	}
}
