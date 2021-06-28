with dtto as (
    select case '{{to}}'::timestamp > now()
       when true then now()
       else '{{to}}'::timestamp
    end as dtto
), prs as (
    select
        *
    from
        (
            select
                distinct id,
                pre.dup_repo_name || '#' || pre.number as pr_key,
                dup_repo_id repo_id,
                dup_repo_name repo_name,
                number,
                user_id author_id,
                dup_user_login author_login,
                created_at,
                last_value(updated_at) over pre_ordered_by_update as last_updated_at,
                last_value(merged_at) over pre_ordered_by_update as last_merged_at,
                last_value(closed_at) over pre_ordered_by_update as last_closed_at
            from
                gha_pull_requests pre
            where
                -- Notice: The metric only counts PRs created within one year.
                created_at >= '{{to}}'::timestamp - '1 year'::interval
                and created_at < '{{to}}'
                and updated_at < '{{to}}'
                and event_id > 0
            window
                pre_ordered_by_update as (
                    partition by id
                    order by
                        updated_at asc,
                        event_id asc
                    range between current row
                    and unbounded following
                )
        ) sub
    where
        last_merged_at is null
        and last_closed_at is null
), prs_reponse_events as (
    (
        select
            event_id,
            pr_key,
            updated_at
        from
            gha_issues ie,
            prs pr
        where
            -- Ignore the response from the PR author.
            ie.dup_actor_id != pr.author_id
            and ie.dup_repo_name = pr.repo_name
            and ie.number = pr.number
            and ie.updated_at > pr.created_at + '30 seconds'::interval
            and ie.updated_at < '{{to}}'
            -- The event type contains IssueEvent and IssueCommentEvent.
            and ie.dup_type like '%Event'
            -- Ignore the robot's response.
            and (lower(ie.dup_actor_login) {{exclude_bots}})
        order by
            ie.updated_at asc
    )
    union
    (
        select
            event_id,
            pr_key,
            updated_at
        from
            gha_pull_requests pre,
            prs pr
        where
            -- Ignore the response from the PR author.
            pre.dup_actor_id != pr.author_id
            and pre.dup_repo_name = pr.repo_name
            and pre.number = pr.number
            and pre.updated_at > pr.created_at + '30 seconds'::interval
            and pre.updated_at < '{{to}}'
            -- The event type contains PullRequestEvent, PullRequestReviewEvent and PullRequestReviewCommentEvent.
            and pre.dup_type like '%Event'
            -- Ignore the robot's response.
            and (lower(pre.dup_actor_login) {{exclude_bots}})
        order by
            pre.updated_at asc
    )
), prs_with_last_issue_event as (
    select
        pr_key,
        i.id issue_id,
        last_value(event_id) over issues_ordered_by_update last_issue_event_id
    from
         prs pr,
         gha_issues i
    where
         pr.repo_name = i.dup_repo_name
         and pr.repo_id = i.dup_repo_id
         and pr.number = i.number
    window
        issues_ordered_by_update as (
            partition by pr.pr_key
            order by
                updated_at asc,
                event_id asc
            range between current row
            and unbounded following
        )
), pr_sig_labels as (
    select
        pr_key,
        sig
    from
    (
        select
            distinct pr_key,
            lower(substring(il.dup_label_name from '(?i)sig/(.*)')) as sig
        from
            gha_issues_labels il,
            prs_with_last_issue_event i
        where
            il.event_id = i.last_issue_event_id
    ) sub
    where
        sig is not null
        and sig in (select sig_mentions_labels_name from tsig_mentions_labels)
), prs_with_stale_time as (
    select
        pr.pr_key,
        repo_name,
        number,
        r.repo_group,
        coalesce(l.sig, 'non-category') as sig,
        -- So far, PingCAP is the company with the largest contribution to the TiDB community,
        -- but other companies may still become the company with the largest contribution.
        case when aa.company_name = 'PingCAP' then 'top-contrib'
             when lower(pr.author_login) like any(array[
                'dependabot', 'ti-srebot', 'codecov-io', 'web-flow',  'prowbot', 'travis%bot', 'k8s-%', '%-bot',
                '%-robot', 'bot-%', 'robot-%', '%[bot]%', '%[robot]%', '%-jenkins', 'jenkins-%', '%-ci%bot',
                '%-testing', 'codecov-%', '%clabot%', '%cla-bot%', '%-gerrit', '%-bot-%', '%cibot', '%-ci'
             ]) then 'only-bots'
             else 'other-company'
        end as author_type,
        coalesce(
            extract(epoch from d.dtto - last_response_at),
            extract(epoch from d.dtto - pr.created_at)
        ) as stale_for
    from
        dtto d,
        prs pr
    left join
        -- Get the last response time for each PR.
        (
            select
                distinct on(prre.pr_key) pr_key,
                last_value(updated_at) over events_ordered_by_update as last_response_at
            from
                prs_reponse_events prre
            window
                events_ordered_by_update as (
                    partition by pr_key
                    order by
                        updated_at asc,
                        event_id asc
                    range between current row
                    and unbounded following
                )
        ) sub
    on
        pr.pr_key = sub.pr_key
    -- Notice: A PR belongs to only one repo group.
    left join
        gha_repos r
    on
        pr.repo_id = r.id
        and pr.repo_name = r.name
    -- Notice: The author of the PR may belong to multiple companies at the same time.
    left join
        gha_actors_affiliations aa
    on
        aa.actor_id = pr.author_id
        and aa.dt_from <= pr.created_at
        and aa.dt_to > pr.created_at
    -- Notice: A PR may belong to multiple SIGs.
    left join
        pr_sig_labels l
    on
        pr.pr_key = l.pr_key
)
select
    'pr_stale_by_sig;' || sub.sig || ';w1,w2,d30,d90' as metric,
    count(distinct sub.pr_key || sub.sig) filter (where sub.stale_for > 604800)  as stale_7,
    count(distinct sub.pr_key || sub.sig) filter (where sub.stale_for > 1209600) as stale_14,
    count(distinct sub.pr_key || sub.sig) filter (where sub.stale_for > 2592000) as stale_30,
    count(distinct sub.pr_key || sub.sig) filter (where sub.stale_for > 7776000) as stale_90
from (
    select
        pst.sig,
        pst.pr_key,
        pst.stale_for
    from
        prs_with_stale_time pst
) sub
group by sub.sig
;
