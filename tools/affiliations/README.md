# affiliations

Collect affiliation information for PingCAP employees.

This program will retrieve the PingCAP employees employee information from lark and merge it with
CNCF's [github_users.json](https://github.com/cncf/devstats/blob/master/github_users.json) data.

Finally, it uploads the merged JSON to AWS S3.

## Usage

To run the program we need to add these environment variables first:

```dotenv
APP_ID= # lark app ID
APP_SECRET= # lark app secret
GITHUB_USERS_JSON_BUCKET= # AWS S3 bucket name
GITHUB_USERS_JSON_BUCKET_KEY= # AWS S3 bucket key
AWS_ACCESS_KEY_ID= # AWS access key ID
AWS_SECRET_ACCESS_KEY= # AWS access secret
AWS_DEFAULT_REGION= # AWS default region
```

Once we have configured these variables, we run the program via `cargo run`.

## Merge Rules

- Current employees
    - If there is no current affiliation information, it is set directly to PingCAP.
    - If the latest current affiliation information is PingCAP, then no action is taken.
    - If the current latest affiliation information is not PingCAP, update the latest affiliation information to
      PingCAP(**The time of joining PingCAP is set to the penultimate company's departure time, because we do not know
      the exact time of joining and have to ignore the current work experience.**).
- Departed PingCAP employees
    - Set the affiliation information to individual developer and set the departure date to the current program run
      date.