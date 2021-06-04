extern crate pretty_env_logger;

#[macro_use]
extern crate serde;
extern crate serde_json;

#[macro_use]
extern crate dotenv_codegen;

#[macro_use]
extern crate log;

use std::collections::HashSet;

use chrono::Utc;
use crawler::crawler::{Crawl, Crawler};

/// Invalid affiliations.
static INVALID_AFFILIATIONS: [&str; 4] = ["", "-", "(Unknown)", "NotFound"];
/// PingCAP affiliation.
static PINGCAP_AFFILIATION: &str = "PingCAP";
/// Independent affiliation.
static INDEPENDENT_AFFILIATION: &str = "Independent";
/// Company separator.
static COMPANY_SEPARATOR: &str = ", ";
/// Date separator.
/// For example: PingCAP < 2021-06-04.
static DATE_SEPARATOR: &str = " < ";

/// GitHub user info.
#[derive(Debug, Serialize, Deserialize)]
struct GitHubUser {
    login: String,
    email: String,
    affiliation: Option<String>,
    source: Option<String>,
    name: Option<String>,
    commits: i64,
    location: Option<String>,
    country_id: Option<String>,
}

#[tokio::main]
async fn main() {
    pretty_env_logger::init();

    info!("Start downloading the github_users file...");
    let resp = reqwest::get(dotenv!("GITHUB_USERS_SOURCE"))
        .await
        .expect("Failed to download the github_users file.")
        .text()
        .await
        .expect("Failed to convert github_users to text.");
    info!("Downloading the github_users file was successful!");

    let mut records: Vec<GitHubUser> =
        serde_json::from_str(resp.as_str()).expect("Failed to parse github_users file.");
    info!("{} records were obtained.", records.len());

    info!("Start fetching the PingCAP GitHub logins...");
    let crawler =
        &Crawler::new(dotenv!("APP_ID"), dotenv!("APP_SECRET")).expect("Failed init the crawler.");
    let logins = crawler
        .list_github_logins()
        .await
        .expect("Failed to list logins.");
    let mut logins: HashSet<&String> = logins.iter().collect::<HashSet<_>>();
    info!("Fetching the logins to succeed!");

    for record in &mut records {
        if logins.contains(&record.login) {
            set_pingcap_affiliation(record);
            logins.remove(&record.login);
        } else {
            remove_pingcap_affiliation(record);
        }
    }

    logins.iter().for_each(|l| {
        info!("Add new record for {}.", l);
        records.push(GitHubUser {
            login: (*l).clone(),
            email: l.as_str().to_owned() + "!users.noreply.github.com",
            affiliation: Some(PINGCAP_AFFILIATION.to_string()),
            source: Some("manual".to_string()),
            name: None,
            commits: 0,
            location: None,
            country_id: None,
        })
    });

    let file =
        std::fs::File::create("github_users.json").expect("Create github_users file failed.");
    serde_json::to_writer_pretty(file, &records).expect("Failed to deserialize.");
}

/// Set PingCAP affiliation to user.
fn set_pingcap_affiliation(user: &mut GitHubUser) {
    match &user.affiliation {
        // If none, set directly to PingCAP.
        None => {
            user.affiliation = {
                info!("Set [{}] affiliation to PingCAP.", user.login);
                Some(PINGCAP_AFFILIATION.to_string())
            }
        }
        Some(affiliation) => {
            // If it is an invalid affiliation, set directly to PingCAP.
            if INVALID_AFFILIATIONS.contains(&affiliation.as_str()) {
                info!(
                    "Set [{}] invalid affiliation `{}` to PingCAP.",
                    user.login, affiliation
                );
                user.affiliation = Some(PINGCAP_AFFILIATION.to_string());
            } else {
                let new_affiliation = generate_new_affiliation_with_pingcap(affiliation);
                match new_affiliation {
                    None => {}
                    Some(new_affiliation) => {
                        info!(
                            "Set [{}] affiliation from `{}` to `{}`.",
                            user.login, affiliation, new_affiliation
                        );
                        user.affiliation = Some(new_affiliation);
                    }
                }
            }
        }
    }
}

/// Remove PingCAP affiliation to user.
fn remove_pingcap_affiliation(user: &mut GitHubUser) {
    match &user.affiliation {
        // None, no need to change.
        None => {}
        Some(affiliation) => {
            // Only when the affiliation is valid.
            if !INVALID_AFFILIATIONS.contains(&affiliation.as_str()) {
                match affiliation
                    .split(COMPANY_SEPARATOR)
                    .collect::<Vec<&str>>()
                    .last()
                {
                    None => {}
                    Some(last) => {
                        // Only if the last company is PingCAP.
                        if *last == PINGCAP_AFFILIATION {
                            let current_date = Utc::now().date().format("%Y-%m-%d").to_string();
                            let new_record = format!(
                                "{}{}{}{}{}",
                                last,
                                DATE_SEPARATOR,
                                current_date,
                                COMPANY_SEPARATOR,
                                INDEPENDENT_AFFILIATION
                            );
                            let mut new_affiliation = affiliation.to_string();
                            new_affiliation.replace_range(
                                affiliation.len() - last.len()..,
                                new_record.as_str(),
                            );
                            info!(
                                "Set [{}] affiliation from `{}` to `{}`.",
                                user.login, affiliation, new_affiliation
                            );
                            user.affiliation = Some(new_affiliation);
                        }
                    }
                }
            }
        }
    }
}

/// Generate new affiliation with PingCAP.
fn generate_new_affiliation_with_pingcap(affiliation: &str) -> Option<String> {
    let pingcap = PINGCAP_AFFILIATION.to_string();
    // The original affiliation look like: "PerkinElmer < 2014-08-01, Independent < 2015-10-01, PwC < 2020-01-01, Simplebet".
    return match affiliation
        .split(COMPANY_SEPARATOR)
        .collect::<Vec<&str>>()
        .as_slice()
    {
        // Get the last two companies.
        // "PerkinElmer < 2014-08-01, Independent < 2015-10-01, PwC < 2020-01-01, Simplebet" ->
        // [.., "PwC < 2020-01-01", "Simplebet" ]
        [.., penultimate, last] => {
            // If the last company is PingCAP then no change is required.
            if *last == PINGCAP_AFFILIATION {
                return None;
            }
            // Set the last company record date to the penultimate company date
            // (Equivalent to ignoring the last company, we can't know exactly when he joined, so we have to do this),
            // then add the pingcap.
            match penultimate
                .split(DATE_SEPARATOR)
                .collect::<Vec<&str>>()
                .first()
            {
                None => panic!("Invalid penultimate affiliation: {}.", penultimate),
                Some(company) => {
                    // Temp: PwC < 2020-01-01 -> Simplebet < 2020-01-01
                    let new_record = penultimate.replace(company, last);

                    // Simplebet -> Simplebet < 2020-01-01
                    let mut new_affiliation = affiliation.to_string();
                    new_affiliation
                        .replace_range(affiliation.len() - last.len().., new_record.as_str());

                    // Finally: "PerkinElmer < 2014-08-01, Independent < 2015-10-01, PwC < 2020-01-01, Simplebet < 2020-01-01, PingCAP"
                    Some(new_affiliation.as_str().to_owned() + COMPANY_SEPARATOR + pingcap.as_str())
                }
            }
        }
        // In other cases where there is only one, replace it directly with PingCAP.
        [last] => {
            // If the last company is PingCAP then no change is required.
            return if *last == PINGCAP_AFFILIATION {
                None
            } else {
                Some(pingcap)
            };
        }
        [] => Some(pingcap),
    };
}

#[cfg(test)]
mod tests {
    use crate::{
        generate_new_affiliation_with_pingcap, remove_pingcap_affiliation, set_pingcap_affiliation,
        GitHubUser,
    };
    use chrono::Utc;

    #[test]
    fn test_generate_new_affiliation_with_pingcap() {
        let cases = vec![
            (
             "PerkinElmer < 2014-08-01, Independent < 2015-10-01, PwC < 2020-01-01, Simplebet",
             (Some("PerkinElmer < 2014-08-01, Independent < 2015-10-01, PwC < 2020-01-01, Simplebet < 2020-01-01, PingCAP".to_string()))
            ),
            (
                "PerkinElmer < 2014-08-01, Independent < 2015-10-01, PwC < 2020-01-01, PingCAP",
           None
            ),
            (
                "PingCAP",
                None
            ),
            (
                "Simplebet",
                Some("PingCAP".to_string())
            ),
            (
                "NotFound",
                Some("PingCAP".to_string())
            ),
            (
                "",
                Some("PingCAP".to_string())
            )
        ];
        for case in cases {
            let affiliation = generate_new_affiliation_with_pingcap(case.0);
            assert_eq!(affiliation, case.1)
        }
    }

    #[test]
    fn test_set_pingcap_affiliation() {
        let cases = vec![
            (
                None, Some("PingCAP".to_string())
            ),
            (
                Some("".to_string()), Some("PingCAP".to_string())
            ),
            (
                Some("-".to_string()), Some("PingCAP".to_string())
            ),
            (
                Some("(Unknown)".to_string()), Some("PingCAP".to_string())
            ),
            (
                Some("".to_string()), Some("PingCAP".to_string())
            ),
            (
                Some("PerkinElmer < 2014-08-01, Independent < 2015-10-01, PwC < 2020-01-01, Simplebet".to_string()),
                Some("PerkinElmer < 2014-08-01, Independent < 2015-10-01, PwC < 2020-01-01, Simplebet < 2020-01-01, PingCAP".to_string())
            ),
            (
                Some("PerkinElmer < 2014-08-01, Independent < 2015-10-01, PwC < 2020-01-01, PingCAP".to_string()),
                Some("PerkinElmer < 2014-08-01, Independent < 2015-10-01, PwC < 2020-01-01, PingCAP".to_string())
            )
        ];

        for case in cases {
            let user = &mut GitHubUser {
                login: "".to_string(),
                email: "".to_string(),
                affiliation: case.0,
                source: None,
                name: None,
                commits: 0,
                location: None,
                country_id: None,
            };
            set_pingcap_affiliation(user);
            assert_eq!(user.affiliation, case.1)
        }
    }

    #[test]
    fn test_remove_pingcap_affiliation() {
        let current_date = Utc::now().date().format("%Y-%m-%d").to_string();

        let cases = vec![
            (
                None, None
            ),
            (
                Some("".to_string()), Some("".to_string())
            ),
            (
                Some("-".to_string()), Some("-".to_string())
            ),
            (
                Some("(Unknown)".to_string()), Some("(Unknown)".to_string())
            ),
            (
                Some("".to_string()), Some("".to_string())
            ),
            (
                Some("PerkinElmer < 2014-08-01, Independent < 2015-10-01, PwC < 2020-01-01, Simplebet".to_string()),
                Some("PerkinElmer < 2014-08-01, Independent < 2015-10-01, PwC < 2020-01-01, Simplebet".to_string())
            ),
            (
                Some("PingCAP".to_string()),
                Some(format!("PingCAP < {}, Independent",current_date))
            ),
            (
                Some("PerkinElmer < 2014-08-01, Independent < 2015-10-01, PwC < 2020-01-01, PingCAP".to_string()),
                Some(format!("PerkinElmer < 2014-08-01, Independent < 2015-10-01, PwC < 2020-01-01, PingCAP < {}, Independent",current_date))
            )
        ];

        for case in cases {
            let user = &mut GitHubUser {
                login: "".to_string(),
                email: "".to_string(),
                affiliation: case.0,
                source: None,
                name: None,
                commits: 0,
                location: None,
                country_id: None,
            };
            remove_pingcap_affiliation(user);
            assert_eq!(user.affiliation, case.1)
        }
    }
}
