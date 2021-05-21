use crate::auth::AuthResp;
use crate::departments::Department;
use crate::resp::{Data, Resp};
use crate::users::User;
use anyhow::{anyhow, Result};
use reqwest::blocking::Client;
use serde::{Deserialize, Serialize};
use std::collections::HashSet;
use std::iter::FromIterator;

pub trait Crawl {
    fn list_github_logins(&self) -> Result<Vec<String>>;
    fn list_departments(&self) -> Result<Vec<String>>;
    fn auth(&self) -> Result<String>;
}

#[derive(Serialize, Deserialize, Debug)]
pub struct AppConfig {
    pub app_id: String,
    pub app_secret: String,
}

pub struct Crawler {
    pub api_url: String,
    pub config: AppConfig,
    pub client: Client,
}

impl Crawl for Crawler {
    fn list_github_logins(&self) -> Result<Vec<String>> {
        let departments = self.list_departments()?;
        let token = self.auth()?;
        let mut results: HashSet<String> = HashSet::new();
        let mut collector = |items: Vec<User>| {
            items
                .iter()
                .filter(|i| i.custom_attrs.is_some())
                .map(|i| {
                    i.custom_attrs
                        .as_ref()
                        .unwrap()
                        .iter()
                        .filter(|c| c.id == "C-6934211695879389211")
                        .map(|c| c.value.text.clone())
                        .collect()
                })
                .for_each(|g| {
                    let _ = results.insert(g);
                });
        };

        for d in departments {
            let mut res = self
                .client
                .get(format!("{}/{}", &self.api_url, "contact/v3/users"))
                .query(&[("department_id", &d)])
                .bearer_auth(&token)
                .send()?
                .json::<Resp<Data<User>>>()?;

            if res.code != 0 {
                return Err(anyhow!("List users failed and msg is {}", res.msg));
            }
            if !res.data.has_more {
                if let Some(items) = res.data.items {
                    collector(items);
                }
            } else {
                while res.data.has_more {
                    if let Some(items) = res.data.items {
                        collector(items);
                    }
                    res = self
                        .client
                        .get(format!("{}/{}", &self.api_url, "contact/v3/users"))
                        .bearer_auth(&token)
                        .query(&[("page_token", res.data.page_token.unwrap())])
                        .query(&[("department_id", &d)])
                        .send()?
                        .json::<Resp<Data<User>>>()?;

                    if res.code != 0 {
                        return Err(anyhow!("List users failed and msg is {}", res.msg));
                    }
                }
            }
        }

        Ok(Vec::from_iter(results))
    }

    fn list_departments(&self) -> Result<Vec<String>> {
        let token = self.auth()?;
        let mut results = vec![];
        let mut collector = |items: Vec<Department>| {
            let departments: Vec<String> =
                items.iter().map(|i| i.open_department_id.clone()).collect();
            results.extend_from_slice(&departments);
        };

        let mut res = self
            .client
            .get(format!("{}/{}", &self.api_url, "contact/v3/departments"))
            .bearer_auth(&token)
            .query(&[("fetch_child", "true")])
            .query(&[("parent_department_id", "0")])
            .send()?
            .json::<Resp<Data<Department>>>()?;

        if res.code != 0 {
            return Err(anyhow!("List departments failed and msg is {}", res.msg));
        }

        if !res.data.has_more {
            if let Some(items) = res.data.items {
                collector(items);
            }
        } else {
            while res.data.has_more {
                if let Some(items) = res.data.items {
                    collector(items);
                }

                res = self
                    .client
                    .get(format!("{}/{}", &self.api_url, "contact/v3/departments"))
                    .bearer_auth(&token)
                    .query(&[("page_token", res.data.page_token.unwrap())])
                    .query(&[("fetch_child", "true")])
                    .query(&[("parent_department_id", "0")])
                    .send()?
                    .json::<Resp<Data<Department>>>()?;

                if res.code != 0 {
                    return Err(anyhow!("List departments failed and msg is {}", res.msg));
                }
            }
        }

        Ok(results)
    }

    fn auth(&self) -> Result<String> {
        let res = self
            .client
            .post(format!(
                "{}/{}",
                &self.api_url, "auth/v3/tenant_access_token/internal/"
            ))
            .json(&self.config)
            .send()?
            .json::<AuthResp>()?;

        if res.code != 0 {
            return Err(anyhow!("Get token failed and msg is {}", res.msg));
        }

        Ok(res.tenant_access_token)
    }
}
