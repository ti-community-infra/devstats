use crate::departments::Department;
use crate::lark::{AppConfig, Lark};
use crate::users::{User, GITHUB_LOGIN_ATTR_ID};
use anyhow::Result;
use async_trait::async_trait;
use std::collections::HashSet;
use std::iter::FromIterator;

#[async_trait]
pub trait Crawl {
    async fn list_github_logins(&self) -> Result<Vec<String>>;
    async fn list_departments(&self) -> Result<Vec<String>>;
}

pub struct Crawler {
    pub(crate) lark: Lark,
}

impl Crawler {
    pub fn new<S>(app_id: S, app_secret: S) -> Result<Self>
    where
        S: Into<String>,
    {
        Ok(Self {
            lark: Lark::new(AppConfig {
                app_id: app_id.into(),
                app_secret: app_secret.into(),
            })?,
        })
    }
}

#[async_trait]
impl Crawl for Crawler {
    /// List all PingCAPer's github logins.
    async fn list_github_logins(&self) -> Result<Vec<String>> {
        let departments = self.list_departments().await?;
        let mut results: HashSet<String> = HashSet::new();

        for d in departments {
            let parameters = vec![("department_id", &d)];
            let res: Vec<User> = self
                .lark
                .list("contact/v3/users", Some(&parameters))
                .await?;

            res.iter()
                .filter(|i| i.custom_attrs.is_some())
                .map(|i| {
                    i.custom_attrs
                        .as_ref()
                        .unwrap()
                        .iter()
                        .filter(|c| c.id == GITHUB_LOGIN_ATTR_ID)
                        .map(|c| c.value.text.clone())
                        .collect()
                })
                .for_each(|g| {
                    results.insert(g);
                });
        }

        Ok(Vec::from_iter(results))
    }

    /// List all PingCAP's departments.
    async fn list_departments(&self) -> Result<Vec<String>> {
        let parameters = vec![("fetch_child", "true"), ("parent_department_id", "0")];

        let res: Vec<Department> = self
            .lark
            .list("contact/v3/departments", Some(&parameters))
            .await?;

        Ok(res.iter().map(|i| i.open_department_id.clone()).collect())
    }
}
