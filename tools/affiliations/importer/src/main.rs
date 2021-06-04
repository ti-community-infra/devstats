extern crate pretty_env_logger;

#[macro_use]
extern crate serde;
extern crate serde_json;

#[macro_use]
extern crate dotenv_codegen;

#[macro_use]
extern crate log;

use crawler::crawler::{Crawl, Crawler};
use std::collections::HashSet;
use std::iter::FromIterator;

static UNKNOWN_AFFILIATION: [&str; 4] = ["", "-", "(Unknown)", "NotFound"];

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
    info!("Start downloading the github_users.json file...");
    let resp = reqwest::get("https://github.com/cncf/gitdm/raw/master/src/github_users.json")
        .await
        .expect("Failed to download the github_users.json file.")
        .text()
        .await
        .expect("Failed to convert github_users.json to users text.");
    info!("Downloading the GitHub_users.json file was successful!");
    let records: Vec<GitHubUser> =
        serde_json::from_str(resp.as_str()).expect("Failed to parse github_users.json.");
    info!("Gets {} users data.", records.len());
    let crawler =
        &Crawler::new(dotenv!("APP_ID"), dotenv!("APP_SECRET")).expect("Failed init the crawler.");
    let logins = crawler
        .list_github_logins()
        .await
        .expect("Failed to get logins.");
    let mut logins: HashSet<&String> = HashSet::from_iter(logins.iter());

    for mut record in records {
        if logins.contains(&record.login) {
            add_pingcap_affiliation(&mut record);
            logins.remove(&record.login);
        }
    }

    println!("Hvae {:#?}", logins.len())
}

fn add_pingcap_affiliation(user: &mut GitHubUser) {
    match &user.affiliation {
        None => {
            user.affiliation = {
                info!("Set {} affiliation to pingcap", user.login,);
                Some("PingCAP".to_string())
            }
        }
        Some(affiliation) => {
            let new_affiliation = get_pingcap_affiliation(affiliation);
            info!(
                "Set {} affiliation from {} to {}",
                user.login, affiliation, new_affiliation
            );
            user.affiliation = Some(new_affiliation);
        }
    }
}

fn get_pingcap_affiliation(affiliation: &String) -> String {
    let pingcap = "PingCAP".to_string();

    if UNKNOWN_AFFILIATION.contains(&affiliation.as_str()) {
        return pingcap.clone();
    }
    return match affiliation.split(", ").collect::<Vec<&str>>().as_slice() {
        [.., second_to_last, last] => {
            if *last == "PingCAP" {
                return affiliation.clone()
            }
            match second_to_last.split(" < ").collect::<Vec<&str>>().first() {
                None => panic!("shouldn't happen"),
                Some(company) => {
                    let new_record = second_to_last.replace(company, last);
                    let new_record = affiliation.replace(last, new_record.as_str());
                    new_record.as_str().to_owned() + ", " + pingcap.as_str()
                }
            }
        }
        _ => pingcap,
    };
}
