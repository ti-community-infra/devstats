select
  *
from (
  values
    ('pr-review'),
    ('misc'),
    ('bug'),
    ('api-review'),
    ('feature-request'),
    ('proposal'),
    ('testlib-failure'),
    ('design-proposal'),
    ('owners'),
  ) as temp(cat)
;
