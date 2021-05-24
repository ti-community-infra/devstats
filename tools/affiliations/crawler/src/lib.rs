mod auth;
pub mod crawler;
mod departments;
mod lark;
mod resp;
mod users;

#[cfg(test)]
mod tests {
    #[test]
    fn it_works() {
        assert_eq!(2 + 2, 4);
    }
}
