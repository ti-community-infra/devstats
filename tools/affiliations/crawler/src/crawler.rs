use crate::departments::Department;
use crate::lark::{AppConfig, Lark};
use crate::resp::{Data, Resp};
use crate::users::User;
use anyhow::{anyhow, Result};
use std::collections::HashSet;
use std::iter::FromIterator;

pub struct Crawler {
    pub lark: Lark,
}

impl Crawler {
    pub fn new(app_id: String, app_secret: String) -> Result<Self> {
        Ok(Self {
            lark: Lark::new(AppConfig { app_id, app_secret })?,
        })
    }
}

impl Crawler {
    pub async fn list_github_logins(&self) -> Result<Vec<String>> {
        let token = self.lark.auth().await?;
        let departments = self.list_departments().await?;
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
            let parameters = vec![("department_id", &d)];
            let mut res: Resp<Data<User>> = self
                .lark
                .get(&token, "contact/v3/users", Some(&parameters))
                .await?;
            if res.code != 0 {
                return Err(anyhow!("List users failed and msg is {}", res.msg));
            }
            if let Some(items) = res.data.items {
                collector(items);
            }

            while let Some(ref page_token) = res.data.page_token {
                let mut new_parm = parameters.clone();
                new_parm.push(("page_token", page_token));
                res = self
                    .lark
                    .get::<Resp<Data<User>>, &String, &str, Vec<(&str, &String)>>(
                        &token,
                        "contact/v3/users",
                        Some(&new_parm),
                    )
                    .await?;
                if res.code != 0 {
                    return Err(anyhow!("List users failed and msg is {}", res.msg));
                }
                if let Some(items) = res.data.items {
                    collector(items);
                }
            }
        }

        Ok(Vec::from_iter(results))
    }

    pub async fn list_departments(&self) -> Result<Vec<String>> {
        let token = self.lark.auth().await?;
        let mut results = vec![];
        let mut collector = |items: Vec<Department>| {
            let departments: Vec<String> =
                items.iter().map(|i| i.open_department_id.clone()).collect();
            results.extend_from_slice(&departments);
        };

        let parameters = vec![("fetch_child", "true"), ("parent_department_id", "0")];
        let mut res: Resp<Data<Department>> = self
            .lark
            .get(&token, "contact/v3/departments", Some(&parameters))
            .await?;
        if res.code != 0 {
            return Err(anyhow!("List departments failed and msg is {}", res.msg));
        }
        if let Some(items) = res.data.items {
            collector(items);
        }

        while let Some(ref page_token) = res.data.page_token {
            let mut new_parm = parameters.clone();
            new_parm.push(("page_token", page_token));
            res = self
                .lark
                .get::<Resp<Data<Department>>, &String, &str, Vec<(&str, &str)>>(
                    &token,
                    "contact/v3/departments",
                    Some(&new_parm),
                )
                .await?;
            if res.code != 0 {
                return Err(anyhow!("List departments failed and msg is {}", res.msg));
            }
            if let Some(items) = res.data.items {
                collector(items);
            }
        }

        Ok(results)
    }
}
