use anyhow::{anyhow, Result};
use reqwest::blocking::Client;
use serde::{Deserialize, Serialize};

use crate::users::UsersResp;
use crate::auth::AuthResp;

pub trait Crawl {
    fn list_github_names(self) -> Result<Vec<String>>;
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
    fn list_github_names(self) -> Result<Vec<String>> {
        let res = self.client.post(format!("{}/{}", &self.api_url, "auth/v3/tenant_access_token/internal/"))
            .json(&self.config)
            .send()?
            .json::<AuthResp>()?;

        if res.code != 0 {
            return Err(anyhow!("Get token failed and msg is {}", res.msg));
        }

        let token = res.tenant_access_token;

        let mut res = self
            .client
            .get(format!("{}/{}", &self.api_url, "contact/v3/users"))
            .bearer_auth(&token)
            .send()?
            .json::<UsersResp>()?;

        if res.code != 0 {
            return Err(anyhow!("List users failed and msg is {}", res.msg));
        }

        let mut results = vec![];

        while res.data.has_more {
            let github_names: Vec<String> = res
                .data
                .items
                .iter()
                .map(|i| {
                    i.custom_attrs
                        .iter()
                        .filter(|c| c.attr_type == "github")
                        .map(|c| c.value.text.clone())
                        .collect()
                })
                .collect();
            results.extend_from_slice(&github_names);

            res = self
                .client
                .get(format!("{}/{}", &self.api_url, "contact/v3/users"))
                .bearer_auth(&token)
                .query(&[("page_token", res.data.page_token.unwrap())])
                .send()?
                .json::<UsersResp>()?;

            if res.code != 0 {
                return Err(anyhow!("List users failed and msg is {}", res.msg));
            }
        }

        Ok(results)
    }
}
