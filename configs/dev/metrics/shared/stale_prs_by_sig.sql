with dtto as (
    select case '{{to}}'::timestamp > now()
       when true then now()
       else '{{to}}'::timestamp
    end as dtto
), issues as (
     select
        sub.issue_id,
        sub.user_id,
        sub.created_at,
        sub.event_id
     from (
        select
            distinct id as issue_id,
            last_value(event_id) over issues_ordered_by_update as event_id,
            first_value(user_id) over issues_ordered_by_update as user_id,
            first_value(created_at) over issues_ordered_by_update as created_at,
            last_value(closed_at) over issues_ordered_by_update as closed_at
        from
            gha_issues
        where
            created_at >= '{{to}}'::timestamp - '1 year'::interval
            and created_at < '{{to}}'
            and updated_at < '{{to}}'
            and is_pull_request = true
            and (lower(dup_user_login) {{exclude_bots}})
            window
            issues_ordered_by_update as (
                partition by id
                order by
                    updated_at asc,
                    event_id asc
                range between current row
                and unbounded following
            )
    ) sub
    where sub.closed_at is null
 ), prs as (
    select
        distinct i.issue_id,
        ipr.pull_request_id as pr_id,
        ipr.number,
        ipr.repo_name,
        pr.created_at,
        pr.user_id,
        i.event_id
    from (
        select
            distinct id as pr_id,
            first_value(user_id) over prs_ordered_by_update as user_id,
            first_value(created_at) over prs_ordered_by_update as created_at,
            last_value(closed_at) over prs_ordered_by_update as closed_at,
            last_value(merged_at) over prs_ordered_by_update as merged_at
        from
            gha_pull_requests
        where
            created_at >= '{{to}}'::timestamp - '1 year'::interval
            and created_at < '{{to}}'
            and updated_at < '{{to}}'
            and event_id > 0
            and (lower(dup_user_login) {{exclude_bots}})
        window
            prs_ordered_by_update as (
                partition by id
                order by
                    updated_at asc,
                    event_id asc
                range between current row
                and unbounded following
            )
        ) pr,
        issues i,
        gha_issues_pull_requests ipr
    where
        ipr.issue_id = i.issue_id
        and ipr.pull_request_id = pr.pr_id
        and pr.closed_at is null
        and pr.merged_at is null
), pr_sigs as (
    select
        sub.issue_id,
        sub.pr_id,
        sub.event_id,
        sub.number,
        sub.repo_name,
        sub.sig
    from (
        select
            pr.issue_id,
            pr.pr_id,
            pr.event_id,
            pr.number,
            pr.repo_name,
            lower(substring(il.dup_label_name from '(?i)sig/(.*)')) as sig
        from
            gha_issues_labels il,
            prs pr
        where
            il.issue_id = pr.issue_id
            and il.event_id = pr.event_id
    ) sub
    where
        sub.sig is not null
        and sub.sig not like '%use-only-as-a-last-resort'
        and sub.sig in (select sig_mentions_labels_name from tsig_mentions_labels)
), issues_last_response as (
    select
        i2.number,
        i2.dup_repo_name as repo_name,
        extract(epoch from d.dtto - i2.updated_at) as diff
    from
        issues i,
        gha_issues i2,
        dtto d
    where
        i.issue_id = i2.id
        and (lower(i2.dup_actor_login) {{exclude_bots}})
        and i2.updated_at < '{{to}}'
        -- Filter out the last action event (IssueCommentEvent / IssueEvent) on issue.
        and i2.event_id in (
            select
                event_id
            from
              gha_issues sub
            where
                sub.dup_actor_id != i.user_id
                and sub.id = i.issue_id
                and i2.updated_at < '{{to}}'
                and sub.updated_at > i.created_at + '30 seconds'::interval
                and sub.dup_type like '%Event'
            order by sub.updated_at desc
            limit 1
        )
), prs_last_reponse as (
    select
        pr2.number,
        pr2.dup_repo_name as repo_name,
        extract(epoch from d.dtto - pr2.updated_at) as diff
    from
        prs pr,
        gha_pull_requests pr2,
        dtto d
    where
        pr.pr_id = pr2.id
        and (lower(pr2.dup_actor_login) {{exclude_bots}})
        and pr2.updated_at < '{{to}}'
        -- Filter out the last action event (PullReviewEvent / PullReviewCommentEvent / PullEvent) on pr.
        and pr2.event_id in (
            select
                event_id
            from
                gha_pull_requests sub
            where
                sub.dup_actor_id != pr.user_id
                and sub.id = pr.pr_id
                and pr2.updated_at < '{{to}}'
                and sub.updated_at > pr.created_at + '30 seconds'::interval
                and sub.dup_type like '%Event'
            order by sub.updated_at desc
            limit 1
        )
), act_on_issue as (
    select
        p.number,
        p.repo_name,
        p.created_at,
        coalesce(ilr.diff, extract(epoch from d.dtto - p.created_at)) as stale_for
    from
        dtto d,
        prs p
    left join
        issues_last_response ilr
    on
        p.repo_name = ilr.repo_name
        and p.number = ilr.number
), act as (
    select
        aoi.number,
        aoi.repo_name,
        least(aoi.stale_for, coalesce(plr.diff, extract(epoch from d.dtto - aoi.created_at))) as stale_for
    from
        dtto d,
        act_on_issue aoi
    left join
        prs_last_reponse plr
    on
        aoi.repo_name = plr.repo_name
        and aoi.number = plr.number
)
select
    'stale_prs_by_sig;' || sub.sig || ';w1,w2,d30,d90' as metric,
    count(distinct sub.pr) filter (where sub.stale_for > 604800)  as stale_7,
    count(distinct sub.pr) filter (where sub.stale_for > 1209600) as stale_14,
    count(distinct sub.pr) filter (where sub.stale_for > 2592000) as stale_30,
    count(distinct sub.pr) filter (where sub.stale_for > 7776000) as stale_90
from (
    select
        s.sig,
        s.repo_name || s.number::text as pr,
        a.stale_for
    from
        pr_sigs s,
        act a
    where
        s.number = a.number
        and s.repo_name = a.repo_name
) sub
group by sub.sig
;