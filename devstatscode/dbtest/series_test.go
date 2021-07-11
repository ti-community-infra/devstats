package dbtest

import (
	"database/sql"
	"testing"
	"time"

	devstatscode "github.com/ti-community-infra/devstats"

	testlib "github.com/ti-community-infra/devstats/test"
)

// Return array of arrays of any values from TSDB result
func getTSDBResult(rows *sql.Rows) (ret [][]interface{}) {
	columns, err := rows.Columns()
	devstatscode.FatalOnError(err)

	// Vals to hold any type as []interface{}
	vals := make([]interface{}, len(columns))
	for i := range columns {
		vals[i] = new([]byte)
	}

	for rows.Next() {
		devstatscode.FatalOnError(rows.Scan(vals...))
		row := []interface{}{}
		for _, val := range vals {
			value := ""
			if val != nil {
				value = string(*val.(*[]byte))
			}
			row = append(row, value)
		}
		ret = append(ret, row)
	}
	devstatscode.FatalOnError(rows.Err())
	return
}

// Return array of arrays of any values from TSDB result
// And postprocess special time values (like now or 1st column from
// quick ranges which has current hours etc) - used for quick ranges
// skipI means that also index "skipI" should skip time now() value (only if additionalSkip is true)
func getTSDBResultFiltered(rows *sql.Rows, additionalSkip bool, skipI []int) (ret [][]interface{}) {
	res := getTSDBResult(rows)
	if len(res) < 1 || len(res[0]) < 1 {
		return
	}
	lastI := len(res) - 1
	lastJ := len(res[0]) - 1
	for i, val := range res {
		skipPeriod := false
		if i == lastI {
			skipPeriod = true
		} else if additionalSkip {
			for _, ii := range skipI {
				if i == ii {
					skipPeriod = true
					break
				}
			}
		}
		row := []interface{}{}
		for j, col := range val {
			// This is a time column, unused, but varies every call
			// j == 0: first unused time col (related to `now`)
			// j == lastJ: last usused value, always 0
			// j == 1 && skipPeriod (last row `version - now`): `now` varies with time
			// or row specified by additionalSkip + skipI
			// Last row's date to is now which also varies every time
			if j == 0 || j == lastJ || (j == 1 && skipPeriod) {
				continue
			}
			row = append(row, col)
		}
		ret = append(ret, row)
	}
	return
}

func TestProcessAnnotations(t *testing.T) {
	// Environment context parse
	var ctx devstatscode.Ctx
	ctx.Init()
	ctx.TestMode = true

	// Do not allow to run tests in "gha" database
	if ctx.PgDB != "dbtest" {
		t.Errorf("tests can only be run on \"dbtest\" database")
		return
	}
	// Drop database if exists
	devstatscode.DropDatabaseIfExists(&ctx)

	// Create database if needed
	createdDatabase := devstatscode.CreateDatabaseIfNeeded(&ctx)
	if !createdDatabase {
		t.Errorf("failed to create database \"%s\"", ctx.PgDB)
	}

	// Connect to Postgres DB
	c := devstatscode.PgConn(&ctx)

	// Drop database after tests
	defer func() {
		devstatscode.FatalOnError(c.Close())
		// Drop database after tests
		devstatscode.DropDatabaseIfExists(&ctx)
	}()

	// Test cases (they will create and close new connection inside ProcessAnnotations)
	ft := testlib.YMDHMS
	earlyDate := ft(2014)
	earlyMiddleDate := ft(2015)
	middleDate := ft(2016)
	middleLateDate := ft(2017)
	lateDate := ft(2018)
	var testCases = []struct {
		annotations         devstatscode.Annotations
		startDate           *time.Time
		joinDate            *time.Time
		incubatingDate      *time.Time
		graduatedDate       *time.Time
		archivedDate        *time.Time
		expectedAnnotations [][]interface{}
		expectedQuickRanges [][]interface{}
		additionalSkip      bool
		skipI               []int
	}{
		{
			annotations: devstatscode.Annotations{
				Annotations: []devstatscode.Annotation{
					{
						Name:        "release 0.0.0",
						Description: "desc 0.0.0",
						Date:        ft(2017, 2),
					},
				},
			},
			startDate: &earlyDate,
			joinDate:  &middleDate,
			expectedAnnotations: [][]interface{}{
				{"2014-01-01T00:00:00Z", "2014-01-01 - project starts", "Project start date"},
				{"2016-01-01T00:00:00Z", "2016-01-01 - joined CNCF", "CNCF join date"},
				{"2017-02-01T00:00:00Z", "desc 0.0.0", "release 0.0.0"},
			},
			expectedQuickRanges: [][]interface{}{
				{"d;1 day;;", "Last day", "d"},
				{"w;1 week;;", "Last week", "w"},
				{"d10;10 days;;", "Last 10 days", "d10"},
				{"m;1 month;;", "Last month", "m"},
				{"q;3 months;;", "Last quarter", "q"},
				{"y;1 year;;", "Last year", "y"},
				{"y2;2 years;;", "Last 2 years", "y2"},
				{"y3;3 years;;", "Last 3 years", "y3"},
				{"y5;5 years;;", "Last 5 years", "y5"},
				{"y10;10 years;;", "Last decade", "y10"},
				{"release 0.0.0 - now", "a_0_n"},
				{"c_b;;2014-01-01 00:00:00;2016-01-01 00:00:00", "Before joining CNCF", "c_b"},
				{"Since joining CNCF", "c_n"},
			},
			additionalSkip: true,
			skipI:          []int{10},
		},
		{
			annotations: devstatscode.Annotations{
				Annotations: []devstatscode.Annotation{
					{
						Name:        "release 0.0.0",
						Description: "desc 0.0.0",
						Date:        ft(2017, 2),
					},
				},
			},
			startDate: &earlyDate,
			joinDate:  &earlyDate,
			expectedAnnotations: [][]interface{}{
				{"2017-02-01T00:00:00Z", "desc 0.0.0", "release 0.0.0"},
			},
			expectedQuickRanges: [][]interface{}{
				{"d;1 day;;", "Last day", "d"},
				{"w;1 week;;", "Last week", "w"},
				{"d10;10 days;;", "Last 10 days", "d10"},
				{"m;1 month;;", "Last month", "m"},
				{"q;3 months;;", "Last quarter", "q"},
				{"y;1 year;;", "Last year", "y"},
				{"y2;2 years;;", "Last 2 years", "y2"},
				{"y3;3 years;;", "Last 3 years", "y3"},
				{"y5;5 years;;", "Last 5 years", "y5"},
				{"y10;10 years;;", "Last decade", "y10"},
				{"release 0.0.0 - now", "a_0_n"},
			},
		},
		{
			annotations: devstatscode.Annotations{
				Annotations: []devstatscode.Annotation{
					{
						Name:        "release 0.0.0",
						Description: "desc 0.0.0",
						Date:        ft(2017, 2),
					},
				},
			},
			startDate: &middleDate,
			joinDate:  &earlyDate,
			expectedAnnotations: [][]interface{}{
				{"2017-02-01T00:00:00Z", "desc 0.0.0", "release 0.0.0"},
			},
			expectedQuickRanges: [][]interface{}{
				{"d;1 day;;", "Last day", "d"},
				{"w;1 week;;", "Last week", "w"},
				{"d10;10 days;;", "Last 10 days", "d10"},
				{"m;1 month;;", "Last month", "m"},
				{"q;3 months;;", "Last quarter", "q"},
				{"y;1 year;;", "Last year", "y"},
				{"y2;2 years;;", "Last 2 years", "y2"},
				{"y3;3 years;;", "Last 3 years", "y3"},
				{"y5;5 years;;", "Last 5 years", "y5"},
				{"y10;10 years;;", "Last decade", "y10"},
				{"release 0.0.0 - now", "a_0_n"},
			},
		},
		{
			annotations: devstatscode.Annotations{
				Annotations: []devstatscode.Annotation{
					{
						Name:        "release 0.0.0",
						Description: "desc 0.0.0",
						Date:        ft(2017, 2),
					},
				},
			},
			startDate: &middleDate,
			expectedAnnotations: [][]interface{}{
				{"2016-01-01T00:00:00Z", "2016-01-01 - project starts", "Project start date"},
				{"2017-02-01T00:00:00Z", "desc 0.0.0", "release 0.0.0"},
			},
			expectedQuickRanges: [][]interface{}{
				{"d;1 day;;", "Last day", "d"},
				{"w;1 week;;", "Last week", "w"},
				{"d10;10 days;;", "Last 10 days", "d10"},
				{"m;1 month;;", "Last month", "m"},
				{"q;3 months;;", "Last quarter", "q"},
				{"y;1 year;;", "Last year", "y"},
				{"y2;2 years;;", "Last 2 years", "y2"},
				{"y3;3 years;;", "Last 3 years", "y3"},
				{"y5;5 years;;", "Last 5 years", "y5"},
				{"y10;10 years;;", "Last decade", "y10"},
				{"release 0.0.0 - now", "a_0_n"},
			},
		},
		{
			annotations: devstatscode.Annotations{
				Annotations: []devstatscode.Annotation{
					{
						Name:        "release 0.0.0",
						Description: "desc 0.0.0",
						Date:        ft(2017, 2),
					},
				},
			},
			expectedAnnotations: [][]interface{}{
				{"2017-02-01T00:00:00Z", "desc 0.0.0", "release 0.0.0"},
			},
			expectedQuickRanges: [][]interface{}{
				{"d;1 day;;", "Last day", "d"},
				{"w;1 week;;", "Last week", "w"},
				{"d10;10 days;;", "Last 10 days", "d10"},
				{"m;1 month;;", "Last month", "m"},
				{"q;3 months;;", "Last quarter", "q"},
				{"y;1 year;;", "Last year", "y"},
				{"y2;2 years;;", "Last 2 years", "y2"},
				{"y3;3 years;;", "Last 3 years", "y3"},
				{"y5;5 years;;", "Last 5 years", "y5"},
				{"y10;10 years;;", "Last decade", "y10"},
				{"release 0.0.0 - now", "a_0_n"},
			},
		},
		{
			joinDate: &earlyDate,
			annotations: devstatscode.Annotations{
				Annotations: []devstatscode.Annotation{
					{
						Name:        "release 0.0.0",
						Description: "desc 0.0.0",
						Date:        ft(2017, 2),
					},
				},
			},
			expectedAnnotations: [][]interface{}{
				{"2014-01-01T00:00:00Z", "2014-01-01 - joined CNCF", "CNCF join date"},
				{"2017-02-01T00:00:00Z", "desc 0.0.0", "release 0.0.0"},
			},
			expectedQuickRanges: [][]interface{}{
				{"d;1 day;;", "Last day", "d"},
				{"w;1 week;;", "Last week", "w"},
				{"d10;10 days;;", "Last 10 days", "d10"},
				{"m;1 month;;", "Last month", "m"},
				{"q;3 months;;", "Last quarter", "q"},
				{"y;1 year;;", "Last year", "y"},
				{"y2;2 years;;", "Last 2 years", "y2"},
				{"y3;3 years;;", "Last 3 years", "y3"},
				{"y5;5 years;;", "Last 5 years", "y5"},
				{"y10;10 years;;", "Last decade", "y10"},
				{"release 0.0.0 - now", "a_0_n"},
			},
		},
		{
			joinDate: &lateDate,
			annotations: devstatscode.Annotations{
				Annotations: []devstatscode.Annotation{
					{
						Name:        "release 0.0.0",
						Description: "desc 0.0.0",
						Date:        ft(2017, 2),
					},
				},
			},
			expectedAnnotations: [][]interface{}{
				{"2017-02-01T00:00:00Z", "desc 0.0.0", "release 0.0.0"},
				{"2018-01-01T00:00:00Z", "2018-01-01 - joined CNCF", "CNCF join date"},
			},
			expectedQuickRanges: [][]interface{}{
				{"d;1 day;;", "Last day", "d"},
				{"w;1 week;;", "Last week", "w"},
				{"d10;10 days;;", "Last 10 days", "d10"},
				{"m;1 month;;", "Last month", "m"},
				{"q;3 months;;", "Last quarter", "q"},
				{"y;1 year;;", "Last year", "y"},
				{"y2;2 years;;", "Last 2 years", "y2"},
				{"y3;3 years;;", "Last 3 years", "y3"},
				{"y5;5 years;;", "Last 5 years", "y5"},
				{"y10;10 years;;", "Last decade", "y10"},
				{"release 0.0.0 - now", "a_0_n"},
			},
		},
		{
			annotations:         devstatscode.Annotations{Annotations: []devstatscode.Annotation{}},
			expectedAnnotations: [][]interface{}{},
			expectedQuickRanges: [][]interface{}{
				{"d;1 day;;", "Last day", "d"},
				{"w;1 week;;", "Last week", "w"},
				{"d10;10 days;;", "Last 10 days", "d10"},
				{"m;1 month;;", "Last month", "m"},
				{"q;3 months;;", "Last quarter", "q"},
				{"y;1 year;;", "Last year", "y"},
				{"y2;2 years;;", "Last 2 years", "y2"},
				{"y3;3 years;;", "Last 3 years", "y3"},
				{"y5;5 years;;", "Last 5 years", "y5"},
				{"Last decade", "y10"},
			},
		},
		{
			annotations: devstatscode.Annotations{
				Annotations: []devstatscode.Annotation{
					{
						Name:        "release 4.0.0",
						Description: "desc 4.0.0",
						Date:        ft(2017, 5),
					},
					{
						Name:        "release 3.0.0",
						Description: "desc 3.0.0",
						Date:        ft(2017, 4),
					},
					{
						Name:        "release 1.0.0",
						Description: "desc 1.0.0",
						Date:        ft(2017, 2),
					},
					{
						Name:        "release 0.0.0",
						Description: "desc 0.0.0",
						Date:        ft(2017, 1),
					},
					{
						Name:        "release 2.0.0",
						Description: "desc 2.0.0",
						Date:        ft(2017, 3),
					},
				},
			},
			expectedAnnotations: [][]interface{}{
				{"2017-01-01T00:00:00Z", "desc 0.0.0", "release 0.0.0"},
				{"2017-02-01T00:00:00Z", "desc 1.0.0", "release 1.0.0"},
				{"2017-03-01T00:00:00Z", "desc 2.0.0", "release 2.0.0"},
				{"2017-04-01T00:00:00Z", "desc 3.0.0", "release 3.0.0"},
				{"2017-05-01T00:00:00Z", "desc 4.0.0", "release 4.0.0"},
			},
			expectedQuickRanges: [][]interface{}{
				{"d;1 day;;", "Last day", "d"},
				{"w;1 week;;", "Last week", "w"},
				{"d10;10 days;;", "Last 10 days", "d10"},
				{"m;1 month;;", "Last month", "m"},
				{"q;3 months;;", "Last quarter", "q"},
				{"y;1 year;;", "Last year", "y"},
				{"y2;2 years;;", "Last 2 years", "y2"},
				{"y3;3 years;;", "Last 3 years", "y3"},
				{"y5;5 years;;", "Last 5 years", "y5"},
				{"y10;10 years;;", "Last decade", "y10"},
				{"a_0_1;;2017-01-01 00:00:00;2017-02-01 00:00:00", "release 0.0.0 - release 1.0.0", "a_0_1"},
				{"a_1_2;;2017-02-01 00:00:00;2017-03-01 00:00:00", "release 1.0.0 - release 2.0.0", "a_1_2"},
				{"a_2_3;;2017-03-01 00:00:00;2017-04-01 00:00:00", "release 2.0.0 - release 3.0.0", "a_2_3"},
				{"a_3_4;;2017-04-01 00:00:00;2017-05-01 00:00:00", "release 3.0.0 - release 4.0.0", "a_3_4"},
				{"release 4.0.0 - now", "a_4_n"},
			},
		},
		{
			annotations: devstatscode.Annotations{
				Annotations: []devstatscode.Annotation{
					{
						Name:        "v1.0",
						Description: "desc v1.0",
						Date:        ft(2016, 1),
					},
					{
						Name:        "v6.0",
						Description: "desc v6.0",
						Date:        ft(2016, 6),
					},
					{
						Name:        "v2.0",
						Description: "desc v2.0",
						Date:        ft(2016, 2),
					},
					{
						Name:        "v4.0",
						Description: "desc v4.0",
						Date:        ft(2016, 4),
					},
					{
						Name:        "v3.0",
						Description: "desc v3.0",
						Date:        ft(2016, 3),
					},
					{
						Name:        "v5.0",
						Description: "desc v5.0",
						Date:        ft(2016, 5),
					},
				},
			},
			expectedAnnotations: [][]interface{}{
				{"2016-01-01T00:00:00Z", "desc v1.0", "v1.0"},
				{"2016-02-01T00:00:00Z", "desc v2.0", "v2.0"},
				{"2016-03-01T00:00:00Z", "desc v3.0", "v3.0"},
				{"2016-04-01T00:00:00Z", "desc v4.0", "v4.0"},
				{"2016-05-01T00:00:00Z", "desc v5.0", "v5.0"},
				{"2016-06-01T00:00:00Z", "desc v6.0", "v6.0"},
			},
			expectedQuickRanges: [][]interface{}{
				{"d;1 day;;", "Last day", "d"},
				{"w;1 week;;", "Last week", "w"},
				{"d10;10 days;;", "Last 10 days", "d10"},
				{"m;1 month;;", "Last month", "m"},
				{"q;3 months;;", "Last quarter", "q"},
				{"y;1 year;;", "Last year", "y"},
				{"y2;2 years;;", "Last 2 years", "y2"},
				{"y3;3 years;;", "Last 3 years", "y3"},
				{"y5;5 years;;", "Last 5 years", "y5"},
				{"y10;10 years;;", "Last decade", "y10"},
				{"a_0_1;;2016-01-01 00:00:00;2016-02-01 00:00:00", "v1.0 - v2.0", "a_0_1"},
				{"a_1_2;;2016-02-01 00:00:00;2016-03-01 00:00:00", "v2.0 - v3.0", "a_1_2"},
				{"a_2_3;;2016-03-01 00:00:00;2016-04-01 00:00:00", "v3.0 - v4.0", "a_2_3"},
				{"a_3_4;;2016-04-01 00:00:00;2016-05-01 00:00:00", "v4.0 - v5.0", "a_3_4"},
				{"a_4_5;;2016-05-01 00:00:00;2016-06-01 00:00:00", "v5.0 - v6.0", "a_4_5"},
				{"v6.0 - now", "a_5_n"},
			},
		},
		{
			annotations: devstatscode.Annotations{
				Annotations: []devstatscode.Annotation{
					{
						Name:        "release 0.0.0",
						Description: "desc 0.0.0",
						Date:        ft(2017, 2),
					},
				},
			},
			startDate:      &earlyDate,
			joinDate:       &earlyMiddleDate,
			incubatingDate: &middleDate,
			graduatedDate:  &middleLateDate,
			archivedDate:   &lateDate,
			expectedAnnotations: [][]interface{}{
				{"2014-01-01T00:00:00Z", "2014-01-01 - project starts", "Project start date"},
				{"2015-01-01T00:00:00Z", "2015-01-01 - joined CNCF", "CNCF join date"},
				{"2016-01-01T00:00:00Z", "2016-01-01 - project moved to incubating state", "Moved to incubating state"},
				{"2017-01-01T00:00:00Z", "2017-01-01 - project graduated", "Graduated"},
				{"2017-02-01T00:00:00Z", "desc 0.0.0", "release 0.0.0"},
				{"2018-01-01T00:00:00Z", "2018-01-01 - project was archived", "Archived"},
			},
			expectedQuickRanges: [][]interface{}{
				{"d;1 day;;", "Last day", "d"},
				{"w;1 week;;", "Last week", "w"},
				{"d10;10 days;;", "Last 10 days", "d10"},
				{"m;1 month;;", "Last month", "m"},
				{"q;3 months;;", "Last quarter", "q"},
				{"y;1 year;;", "Last year", "y"},
				{"y2;2 years;;", "Last 2 years", "y2"},
				{"y3;3 years;;", "Last 3 years", "y3"},
				{"y5;5 years;;", "Last 5 years", "y5"},
				{"y10;10 years;;", "Last decade", "y10"},
				{"release 0.0.0 - now", "a_0_n"},
				{"c_b;;2014-01-01 00:00:00;2015-01-01 00:00:00", "Before joining CNCF", "c_b"},
				{"Since joining CNCF", "c_n"},
				{"c_j_i;;2015-01-01 00:00:00;2016-01-01 00:00:00", "CNCF join date - moved to incubation", "c_j_i"},
				{"c_i_g;;2016-01-01 00:00:00;2017-01-01 00:00:00", "Moved to incubation - graduated", "c_i_g"},
				{"Since graduating", "c_g_n"},
			},
			additionalSkip: true,
			skipI:          []int{10, 12},
		},
		{
			annotations: devstatscode.Annotations{
				Annotations: []devstatscode.Annotation{
					{
						Name:        "release 0.0.0",
						Description: "desc 0.0.0",
						Date:        ft(2017, 2),
					},
				},
			},
			startDate:      &earlyDate,
			joinDate:       nil,
			incubatingDate: &middleDate,
			graduatedDate:  &middleLateDate,
			archivedDate:   &lateDate,
			expectedAnnotations: [][]interface{}{
				{"2014-01-01T00:00:00Z", "2014-01-01 - project starts", "Project start date"},
				{"2016-01-01T00:00:00Z", "2016-01-01 - project moved to incubating state", "Moved to incubating state"},
				{"2017-01-01T00:00:00Z", "2017-01-01 - project graduated", "Graduated"},
				{"2017-02-01T00:00:00Z", "desc 0.0.0", "release 0.0.0"},
				{"2018-01-01T00:00:00Z", "2018-01-01 - project was archived", "Archived"},
			},
			expectedQuickRanges: [][]interface{}{
				{"d;1 day;;", "Last day", "d"},
				{"w;1 week;;", "Last week", "w"},
				{"d10;10 days;;", "Last 10 days", "d10"},
				{"m;1 month;;", "Last month", "m"},
				{"q;3 months;;", "Last quarter", "q"},
				{"y;1 year;;", "Last year", "y"},
				{"y2;2 years;;", "Last 2 years", "y2"},
				{"y3;3 years;;", "Last 3 years", "y3"},
				{"y5;5 years;;", "Last 5 years", "y5"},
				{"y10;10 years;;", "Last decade", "y10"},
				{"release 0.0.0 - now", "a_0_n"},
			},
			additionalSkip: true,
			skipI:          []int{10, 12},
		},
		{
			annotations: devstatscode.Annotations{
				Annotations: []devstatscode.Annotation{
					{
						Name:        "release 0.0.0",
						Description: "desc 0.0.0",
						Date:        ft(2017, 2),
					},
				},
			},
			startDate:      &earlyDate,
			joinDate:       &earlyMiddleDate,
			incubatingDate: &middleDate,
			expectedAnnotations: [][]interface{}{
				{"2014-01-01T00:00:00Z", "2014-01-01 - project starts", "Project start date"},
				{"2015-01-01T00:00:00Z", "2015-01-01 - joined CNCF", "CNCF join date"},
				{"2016-01-01T00:00:00Z", "2016-01-01 - project moved to incubating state", "Moved to incubating state"},
				{"2017-02-01T00:00:00Z", "desc 0.0.0", "release 0.0.0"},
			},
			expectedQuickRanges: [][]interface{}{
				{"d;1 day;;", "Last day", "d"},
				{"w;1 week;;", "Last week", "w"},
				{"d10;10 days;;", "Last 10 days", "d10"},
				{"m;1 month;;", "Last month", "m"},
				{"q;3 months;;", "Last quarter", "q"},
				{"y;1 year;;", "Last year", "y"},
				{"y2;2 years;;", "Last 2 years", "y2"},
				{"y3;3 years;;", "Last 3 years", "y3"},
				{"y5;5 years;;", "Last 5 years", "y5"},
				{"y10;10 years;;", "Last decade", "y10"},
				{"release 0.0.0 - now", "a_0_n"},
				{"c_b;;2014-01-01 00:00:00;2015-01-01 00:00:00", "Before joining CNCF", "c_b"},
				{"Since joining CNCF", "c_n"},
				{"c_j_i;;2015-01-01 00:00:00;2016-01-01 00:00:00", "CNCF join date - moved to incubation", "c_j_i"},
				{"Since moving to incubating state", "c_i_n"},
			},
			additionalSkip: true,
			skipI:          []int{10, 12},
		},
		{
			annotations: devstatscode.Annotations{
				Annotations: []devstatscode.Annotation{
					{
						Name:        "release 0.0.0",
						Description: "desc 0.0.0",
						Date:        ft(2017, 2),
					},
				},
			},
			startDate:     &earlyDate,
			joinDate:      &earlyMiddleDate,
			graduatedDate: &middleLateDate,
			expectedAnnotations: [][]interface{}{
				{"2014-01-01T00:00:00Z", "2014-01-01 - project starts", "Project start date"},
				{"2015-01-01T00:00:00Z", "2015-01-01 - joined CNCF", "CNCF join date"},
				{"2017-01-01T00:00:00Z", "2017-01-01 - project graduated", "Graduated"},
				{"2017-02-01T00:00:00Z", "desc 0.0.0", "release 0.0.0"},
			},
			expectedQuickRanges: [][]interface{}{
				{"d;1 day;;", "Last day", "d"},
				{"w;1 week;;", "Last week", "w"},
				{"d10;10 days;;", "Last 10 days", "d10"},
				{"m;1 month;;", "Last month", "m"},
				{"q;3 months;;", "Last quarter", "q"},
				{"y;1 year;;", "Last year", "y"},
				{"y2;2 years;;", "Last 2 years", "y2"},
				{"y3;3 years;;", "Last 3 years", "y3"},
				{"y5;5 years;;", "Last 5 years", "y5"},
				{"y10;10 years;;", "Last decade", "y10"},
				{"release 0.0.0 - now", "a_0_n"},
				{"c_b;;2014-01-01 00:00:00;2015-01-01 00:00:00", "Before joining CNCF", "c_b"},
				{"Since joining CNCF", "c_n"},
				{"c_j_g;;2015-01-01 00:00:00;2017-01-01 00:00:00", "CNCF join date - graduated", "c_j_g"},
				{"Since graduating", "c_g_n"},
			},
			additionalSkip: true,
			skipI:          []int{10, 12},
		},
		{
			annotations: devstatscode.Annotations{
				Annotations: []devstatscode.Annotation{
					{
						Name:        "release 0.0.0",
						Description: "desc 0.0.0",
						Date:        ft(2017, 2),
					},
				},
			},
			startDate:      &earlyDate,
			joinDate:       &earlyMiddleDate,
			graduatedDate:  &middleDate,
			incubatingDate: &middleLateDate,
			archivedDate:   &lateDate,
			expectedAnnotations: [][]interface{}{
				{"2014-01-01T00:00:00Z", "2014-01-01 - project starts", "Project start date"},
				{"2015-01-01T00:00:00Z", "2015-01-01 - joined CNCF", "CNCF join date"},
				{"2016-01-01T00:00:00Z", "2016-01-01 - project graduated", "Graduated"},
				{"2017-01-01T00:00:00Z", "2017-01-01 - project moved to incubating state", "Moved to incubating state"},
				{"2017-02-01T00:00:00Z", "desc 0.0.0", "release 0.0.0"},
				{"2018-01-01T00:00:00Z", "2018-01-01 - project was archived", "Archived"},
			},
			expectedQuickRanges: [][]interface{}{
				{"d;1 day;;", "Last day", "d"},
				{"w;1 week;;", "Last week", "w"},
				{"d10;10 days;;", "Last 10 days", "d10"},
				{"m;1 month;;", "Last month", "m"},
				{"q;3 months;;", "Last quarter", "q"},
				{"y;1 year;;", "Last year", "y"},
				{"y2;2 years;;", "Last 2 years", "y2"},
				{"y3;3 years;;", "Last 3 years", "y3"},
				{"y5;5 years;;", "Last 5 years", "y5"},
				{"y10;10 years;;", "Last decade", "y10"},
				{"release 0.0.0 - now", "a_0_n"},
				{"c_b;;2014-01-01 00:00:00;2015-01-01 00:00:00", "Before joining CNCF", "c_b"},
				{"Since joining CNCF", "c_n"},
			},
			additionalSkip: true,
			skipI:          []int{10},
		},
	}
	// Execute test cases
	for index, test := range testCases {
		// Execute annotations & quick ranges call
		devstatscode.ProcessAnnotations(&ctx, &test.annotations, []*time.Time{test.startDate, test.joinDate, test.incubatingDate, test.graduatedDate, test.archivedDate})

		// Check annotations created
		rows := devstatscode.QuerySQLWithErr(c, &ctx, "select time, description, title from \"sannotations\" order by time asc")
		gotAnnotations := getTSDBResult(rows)
		devstatscode.FatalOnError(rows.Close())
		if !testlib.CompareSlices2D(test.expectedAnnotations, gotAnnotations) {
			t.Errorf(
				"test number %d: join date: %+v\nannotations: %+v\nExpected annotations:\n%+v\n%+v\ngot.",
				index+1, test.joinDate, test.annotations, test.expectedAnnotations, gotAnnotations,
			)
		}

		// Clean up for next test
		devstatscode.ExecSQLWithErr(c, &ctx, "delete from \"sannotations\"")

		// Check Quick Ranges created
		// Results contains some time values depending on current time ..Filtered func handles this
		rows = devstatscode.QuerySQLWithErr(c, &ctx, "select time, quick_ranges_data, quick_ranges_name, quick_ranges_suffix, 0 from \"tquick_ranges\" order by time asc")
		gotQuickRanges := getTSDBResultFiltered(rows, test.additionalSkip, test.skipI)
		devstatscode.FatalOnError(rows.Close())
		if !testlib.CompareSlices2D(test.expectedQuickRanges, gotQuickRanges) {
			t.Errorf(
				"test number %d: join date: %+v\nannotations: %+v\nExpected quick ranges:\n%+v\n%+v\ngot",
				index+1, test.joinDate, test.annotations, test.expectedQuickRanges, gotQuickRanges,
			)
		}
		// Clean up for next test
		devstatscode.ExecSQLWithErr(c, &ctx, "delete from \"tquick_ranges\"")
	}
}