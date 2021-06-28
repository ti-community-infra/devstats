delete from dashboard_tag where dashboard_id = (select id from dashboard where slug = 'dashboards');

insert into dashboard_tag(dashboard_id, term) values((select id from dashboard where slug = 'dashboards'), 'home');
insert into dashboard_tag(dashboard_id, term) values((select id from dashboard where slug = 'dashboards'), 'all');
insert into dashboard_tag(dashboard_id, term) values((select id from dashboard where slug = 'dashboards'), 'pingcap');

update dashboard set id = 1001  where slug = 'community-sizing-and-health-assessment';
update dashboard set id = 1002  where slug = 'contributor-statistics';
update dashboard set id = 1003  where slug = 'company-group';
update dashboard set id = 1004  where slug = 'pr-velocity';
update dashboard set id = 1005  where slug = 'issue-velocity';
update dashboard set id = 1006  where slug = 'comment';

update
  dashboard
set
  is_folder = 1
where
  slug in (
    'community-sizing-and-health-assessment',
    'contributor-statistics',
    'company-group',
    'pr-velocity',
    'issue-velocity',
    'comment'
  )
;

update
  dashboard
set
  folder_id = (
    select
      id
    from
      dashboard
    where
      slug = 'community-sizing-and-health-assessment'
  )
where
  slug in (
    'activity-repository-groups',
    'countries-statistics-in-repository-groups',
    'github-events',
    'overall-project-statistics-table',
    'repository-groups',
    'stars-and-forks-by-repository',
    'users-statistics-by-repository-group'
  )
;

update
  dashboard
set
  folder_id = (
    select
      id
    from
      dashboard
    where
      slug = 'contributor-statistics'
  )
where
  slug in (
    'commits-repository-groups',
    'contributions-chart',
    'contributor-profile',
    'developer-activity-counts-by-repository-group-table',
    'documentation-committers-in-repository-groups',
    'new-and-episodic-pr-contributors',
    'new-contributors-table'
  )
;

update
  dashboard
set
  folder_id = (
    select
      id
    from
      dashboard
    where
      slug = 'company-group'
  )
where
  slug in (
    'companies-contributing-in-repository-groups',
    'companies-table',
    'company-commits-table',
    'company-prs-in-repository-groups-table',
    'company-statistics-by-repository-group',
    'developer-activity-counts-by-companies',
    'prs-authors-companies-table'
  )
;


update
  dashboard
set
  folder_id = (
    select
      id
    from
      dashboard
    where
      slug = 'pr-velocity'
  )
where
  slug in (
    'prs-opened-in-repository-groups',
    'prs-merged-in-repository-groups',
    'prs-closed-in-repository-groups',
    'open-pr-age-by-repository-group',
    'pr-reviews-by-contributor',
    'pr-time-open-to-first-response',
    'prs-approval-repository-groups',
    'prs-authors-repository-groups',
    'prs-authors-table',
    'prs-mergers-table',
    'time-to-merge-in-repository-groups',
    'stale-prs-by-sig'
  )
;

update
  dashboard
set
  folder_id = (
    select
      id
    from
      dashboard
    where
      slug = 'issue-velocity'
  )
where
  slug in (
    'issues-age-by-repository-group',
    'issue-time-to-first-comment',
    'issues-opened-closed-by-repository-group',
    'new-and-episodic-issue-creators'
  )
;

update
  dashboard
set
  folder_id = (
    select
      id
    from
      dashboard
    where
      slug = 'comment'
  )
where
  slug in (
    'pr-comments',
    'repository-commenters',
    'repository-comments',
    'top-commenters-table'
  )
;

select id, uid, folder_id, is_folder, slug, title from dashboard;
