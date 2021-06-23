with prs as (
    select
        pr.event_id,
        pr.id,
        pr.dup_repo_name repo_name,
        pr.number,
        pr.created_at,
        pr.merged_at,
        case when aa.company_name = 'PingCAP' then 'is-top-contributing-company'
             when lower(pr.dup_user_login) like any(array[
                'dependabot', 'ti-srebot', 'codecov-io', 'web-flow',  'prowbot', 'travis%bot', 'k8s-%', '%-bot',
                '%-robot', 'bot-%', 'robot-%', '%[bot]%', '%[robot]%', '%-jenkins', 'jenkins-%', '%-ci%bot',
                '%-testing', 'codecov-%', '%clabot%', '%cla-bot%', '%-gerrit', '%-bot-%', '%cibot', '%-ci'
             ]) then 'only-bots'
             else 'not-top-contributing-company'
        end as author_type
    from
        gha_pull_requests pr
    left join
        gha_actors_affiliations aa
    on
        aa.actor_id = pr.user_id
        and aa.dt_from <= pr.created_at
        and aa.dt_to > pr.created_at
    where
        pr.merged_at is not null
        and pr.created_at >= '{{from}}'
        and pr.created_at < '{{to}}'
        -- Select the latest pr event.
        and pr.event_id = (
            select i.event_id from gha_pull_requests i where i.id = pr.id order by i.updated_at desc limit 1
        )
), prs_groups as (
    select
        pr.event_id,
        pr.id,
        pr.dup_repo_name repo_name,
        pr.number,
        r.repo_group,
        case when aa.company_name = 'PingCAP' then 'is-top-contributing-company'
             when lower(pr.dup_user_login) like any(array[
                'dependabot', 'ti-srebot', 'codecov-io', 'web-flow',  'prowbot', 'travis%bot', 'k8s-%', '%-bot',
                '%-robot', 'bot-%', 'robot-%', '%[bot]%', '%[robot]%', '%-jenkins', 'jenkins-%', '%-ci%bot',
                '%-testing', 'codecov-%', '%clabot%', '%cla-bot%', '%-gerrit', '%-bot-%', '%cibot', '%-ci'
             ]) then 'only-bots'
             else 'not-top-contributing-company'
        end as author_type,
        pr.created_at,
        pr.merged_at as merged_at
    from
        gha_repos r,
        gha_pull_requests pr
    left join
        gha_actors_affiliations aa
    on
        aa.actor_id = pr.user_id
        and aa.dt_from <= pr.created_at
        and aa.dt_to > pr.created_at
    where
        r.id = pr.dup_repo_id
        and r.name = pr.dup_repo_name
        and r.repo_group is not null
        and pr.merged_at is not null
        and pr.created_at >= '{{from}}'
        and pr.created_at < '{{to}}'
        -- Select the latest pr event.
        and pr.event_id = (
            select i.event_id from gha_pull_requests i where i.id = pr.id order by i.updated_at desc limit 1
        )
), prs_sigs_label as (
    select
      distinct sub.id,
      sub.sig
    from (
      select
        p.id,
        lower(substring(il.dup_label_name from '(?i)sig/(.*)')) as sig
      from
        gha_issues_labels il,
        prs p
      where
        il.dup_repo_name = p.repo_name
        and il.dup_issue_number = p.number
      ) sub
    where
      sub.sig is not null
      and sub.sig in (select sig_mentions_labels_name from tsig_mentions_labels)
), prs_with_sigs as (
    select
        pr.event_id,
        pr.id,
        pr.repo_name,
        psl.sig,
        pr.number,
        pr.created_at,
        pr.merged_at,
        author_type
    from
        prs pr
    left join
        prs_sigs_label psl
    on
        pr.id = psl.id
), prs_groups_with_sigs as (
    select
        pr.event_id,
        pr.id,
        pr.repo_group,
        pr.repo_name,
        psl.sig,
        pr.number,
        pr.created_at,
        pr.merged_at,
        author_type
    from
        prs_groups pr
    left join
        prs_sigs_label psl
    on
        pr.id = psl.id
), tdiffs as (
    select
        id,
        sig,
        author_type,
        extract(epoch from merged_at - created_at) / 3600 as open_to_merge
    from
        prs_with_sigs ps
), tdiffs_groups as (
    select
        id,
        sig,
        repo_group,
        author_type,
        extract(epoch from merged_at - created_at) / 3600 as open_to_merge
    from
        prs_groups_with_sigs
)
-- all repository, all author type, all sig.
select
    'open2merge_sig;All_All_All;p15,med,p85' as name,
    percentile_disc(0.15) within group (order by open_to_merge asc) as open_to_merge_15_percentile,
    percentile_disc(0.5) within group (order by open_to_merge asc) as open_to_merge_median,
    percentile_disc(0.85) within group (order by open_to_merge asc) as open_to_merge_85_percentile
from
    tdiffs
-- all repository, author type group, all sig.
union
(
    select
        'open2merge_sig;All_' || author_type || '_All;p15,med,p85' as name,
        percentile_disc(0.15) within group (order by open_to_merge asc) as open_to_merge_15_percentile,
        percentile_disc(0.5) within group (order by open_to_merge asc) as open_to_merge_median,
        percentile_disc(0.85) within group (order by open_to_merge asc) as open_to_merge_85_percentile
    from
        tdiffs
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
        tdiffs_groups
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
        tdiffs_groups
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
        tdiffs
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
        tdiffs
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
        tdiffs_groups
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
        tdiffs_groups
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