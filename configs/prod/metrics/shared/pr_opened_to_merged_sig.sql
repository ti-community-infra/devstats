with prs as (
    select
        pre.id,
        pre.dup_repo_name || '#' || pre.number as pr_key,
        pre.dup_repo_id repo_id,
        pre.dup_repo_name repo_name,
        pre.number,
        pre.user_id author_id,
        pre.dup_user_login author_login,
        pre.created_at,
        pre.merged_at
    from
        gha_pull_requests pre
    where
        pre.merged_at is not null
        and pre.created_at >= '{{from}}'
        and pre.created_at < '{{to}}'
        -- Select the latest pr event.
        and pre.event_id = (
            select
               last_pre.event_id
            from
                gha_pull_requests last_pre
            where
                last_pre.id = pre.id
            order by
                last_pre.updated_at desc
            limit 1
        )
), pr_with_last_issue_event as (
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
            pr_with_last_issue_event i
        where
            il.event_id = i.last_issue_event_id
    ) sub
    where
        sig is not null
        and sig in (select sig_mentions_labels_name from tsig_mentions_labels)
), pr_tdiff as (
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
        extract(epoch from pr.merged_at - pr.created_at) / 3600 as open_to_merge
    from
        prs pr
    -- Notice: A PR belongs to only one repo group.
    left join
        gha_repos r
    on
        repo_id = r.id
        and repo_name = r.name
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
-- all repository, all author type, all sig.
select
    'open2merge_sig;All_All_All;p15,med,p85' as name,
    percentile_disc(0.15) within group (order by open_to_merge asc) as open_to_merge_15_percentile,
    percentile_disc(0.5) within group (order by open_to_merge asc) as open_to_merge_median,
    percentile_disc(0.85) within group (order by open_to_merge asc) as open_to_merge_85_percentile
from
    (
        select
            distinct on (pr_key)
            open_to_merge
        from
            pr_tdiff
    ) sub
-- all repository, author type group, all sig.
union
(
    select
        'open2merge_sig;All_' || author_type || '_All;p15,med,p85' as name,
        percentile_disc(0.15) within group (order by open_to_merge asc) as open_to_merge_15_percentile,
        percentile_disc(0.5) within group (order by open_to_merge asc) as open_to_merge_median,
        percentile_disc(0.85) within group (order by open_to_merge asc) as open_to_merge_85_percentile
    from
        (
            select
                distinct on (pr_key || author_type)
                author_type,
                open_to_merge
            from
                pr_tdiff
        ) sub
    where
        author_type is not null
    group by
        author_type
)
-- repository group, all author type, all sig.
union
(
    select
        'open2merge_sig;' || repo_group || '_All_All;p15,med,p85' as name,
        percentile_disc(0.15) within group (order by open_to_merge asc) as open_to_merge_15_percentile,
        percentile_disc(0.5) within group (order by open_to_merge asc) as open_to_merge_median,
        percentile_disc(0.85) within group (order by open_to_merge asc) as open_to_merge_85_percentile
    from
        (
            select
                distinct on (pr_key || repo_group)
                repo_group,
                open_to_merge
            from
                pr_tdiff
        ) sub
    where
        repo_group is not null
    group by
        repo_group
    order by
        open_to_merge_median desc,
        name
)
-- repository group, author type group, all sig.
union
(
    select
        'open2merge_sig;' || repo_group || '_' || author_type || '_All;p15,med,p85' as name,
        percentile_disc(0.15) within group (order by open_to_merge asc) as open_to_merge_15_percentile,
        percentile_disc(0.5) within group (order by open_to_merge asc) as open_to_merge_median,
        percentile_disc(0.85) within group (order by open_to_merge asc) as open_to_merge_85_percentile
    from
        (
            select
                distinct on (pr_key || repo_group || author_type)
                repo_group,
                author_type,
                open_to_merge
            from
                pr_tdiff
        ) sub
    where
        author_type is not null
        and repo_group is not null
    group by
        repo_group,
        author_type
    order by
        open_to_merge_median desc,
        name
)
union
-- all repository, all author type, sig group.
(
    select
        'open2merge_sig;All_All_' || sig || ';p15,med,p85' as name,
        percentile_disc(0.15) within group (order by open_to_merge asc) as open_to_merge_15_percentile,
        percentile_disc(0.5) within group (order by open_to_merge asc) as open_to_merge_median,
        percentile_disc(0.85) within group (order by open_to_merge asc) as open_to_merge_85_percentile
    from
        (
            select
                distinct on (pr_key || sig)
                sig,
                open_to_merge
            from
                pr_tdiff
        ) sub
    where
        sig is not null
    group by
        sig
)
-- all repository, author type group, sig group.
union
(
    select
        'open2merge_sig;All_' || author_type || '_' || sig || ';p15,med,p85' as name,
        percentile_disc(0.15) within group (order by open_to_merge asc) as open_to_merge_15_percentile,
        percentile_disc(0.5) within group (order by open_to_merge asc) as open_to_merge_median,
        percentile_disc(0.85) within group (order by open_to_merge asc) as open_to_merge_85_percentile
    from
        (
            select
                distinct on (pr_key || author_type || sig)
                author_type,
                sig,
                open_to_merge
            from
                pr_tdiff
        ) sub
    where
        author_type is not null
        and sig is not null
    group by
        author_type,
        sig
)
-- repository group, all author type, sig group.
union
(
    select
        'open2merge_sig;' || repo_group || '_All_' || sig || ';p15,med,p85' as name,
        percentile_disc(0.15) within group (order by open_to_merge asc) as open_to_merge_15_percentile,
        percentile_disc(0.5) within group (order by open_to_merge asc) as open_to_merge_median,
        percentile_disc(0.85) within group (order by open_to_merge asc) as open_to_merge_85_percentile
    from
        (
            select
                distinct on (pr_key || repo_group || sig)
                repo_group,
                sig,
                open_to_merge
            from
                pr_tdiff
        ) sub
    where
        repo_group is not null
        and sig is not null
    group by
        repo_group,
        sig
    order by
        open_to_merge_median desc,
        name
)
-- repository group, author type group, sig group.
union
(
    select
        'open2merge_sig;' || repo_group || '_' || author_type || '_' || sig || ';p15,med,p85' as name,
        percentile_disc(0.15) within group (order by open_to_merge asc) as open_to_merge_15_percentile,
        percentile_disc(0.5) within group (order by open_to_merge asc) as open_to_merge_median,
        percentile_disc(0.85) within group (order by open_to_merge asc) as open_to_merge_85_percentile
    from
        (
            select
                distinct on (pr_key || repo_group || author_type || sig)
                repo_group,
                author_type,
                sig,
                open_to_merge
            from
                pr_tdiff
        ) sub
    where
        author_type is not null
        and repo_group is not null
        and sig is not null
    group by
        repo_group,
        author_type,
        sig
    order by
        open_to_merge_median desc,
        name
)
;