{% set cfg = opts['ms_project'] %}
{% set data = cfg.data %}
{% set users_bases = {} %}
{% set admins = users_bases.setdefault('admins', []) %}
{% set readonlys = users_bases.setdefault('readonlys', []) %}
{% set http_users = {} %}


{% for readonly in salt['mc_utils.uniquify'](
                      data.get('readonlys', []) + ["admin"]) %}
{%  if readonly not in readonlys %}
{%    do readonlys.append(readonly) %}
{%  endif %}
{%  if readonly not in http_users %}
{%  do http_users.update({
      readonly: salt['mc_utils.generate_stored_password'](
        "ESuser_{0}".format(readonly))})%}
{%  endif %}
{% endfor %}

# load users
{% for userdict in data.get('users', []) %}
{%  for user, userdata in userdict.items() %}
{%   do http_users.update({user: userdata.get(
      'password',
      salt['mc_utils.generate_stored_password'](
        '{0}.es_user_{1}'.format(cfg.name, user)))}) %}
{%  endfor %}
{% endfor %}

{% for dbext in data.get('indexes', {}) %}
{%  for db, dbdata in dbext.items() %}
{%    for user in dbdata.get('users', []) %}
{%      if user not in http_users %}
{%        do http_users.update(
            {user: salt['mc_utils.generate_stored_password'](
             '{0}.es_user_{1}'.format(cfg.name, user))}) %}
{%      endif %}
{%      set usersbase = users_bases.setdefault(db, []) %}
{%      do usersbase.append(user) %}
{%    endfor %}
{%  endfor %}
{% endfor %}

# make per type auth files
{% for dbext in data.get('indexes', {}) %}
{%  for db, dbdata in dbext.items() %}
{%    for typ, typdata in dbdata.get('types', {}).items() %}
{%      for user in typdata.get('users', []) %}
{%        if user not in http_users %}
{%          do http_users.update(
              {user: salt['mc_utils.generate_stored_password'](
               '{0}.es_user_{1}'.format(cfg.name, user))}) %}
{%        endif %}
{%        set usersbase = users_bases.setdefault(
                  '{0}___{1}'.format(db, typ),
                  salt['mc_utils.deepcopy'](users_bases[db])) %}
{%        do usersbase.append(user) %}
{%      endfor %}
{%    endfor %}
{%  endfor %}
{% endfor %}

{#
# in case of firewall: we respect groups from the admins key
# and in case of passthrough, we just take the whole users subkey as admins
#}
{% set admin_users = data.get('admins', []) + ["admin"] %}
{% if data.get('http_proxy_passthrough', False) %}
{% set admin_users = [] %}
{% for userdict in data.users %}
{% for i, data in userdict.items() %}
{% set admin_users = admin_users.append(i) %}
{% endfor%}
{% endfor%}
{% endif %}
{% set admin_users = salt['mc_utils.uniquify'](admin_users) %}
{% for admin in admin_users %}
{%  if admin not in admins %}
{%    do admins.append(admin) %}
{%  endif %}
{%  if admin not in http_users %}
{%  do http_users.update({
      admin: salt['mc_utils.generate_stored_password'](
        "ESuser_{0}".format(admin))})%}
{%  endif %}
{% endfor %}

{# for each index, + the admin root, we generate a specific htpasswd file
   that we will use to restrict access via nginx to elasticsearch http endpoint #}
{% for users_base, users in users_bases.items() %}
{% set fl = data.htpasswd_base.format(cfg.name, users_base) %}
"{{cfg.name}}-{{users_base}}-htpasswd-a":
  file.absent:
    - name: "{{fl}}"
"{{cfg.name}}-{{users_base}}-htpasswd":
  file.managed:
    - name: "{{fl}}"
    - contents: ''
    - makedirs: true
    - user: www-data
    - group: www-data
    - mode: 770
    - require:
      - file: "{{cfg.name}}-{{users_base}}-htpasswd-a"

{% set users = salt['mc_utils.uniquify'](users + admins) %}
{% for user in users %}
"{{cfg.name}}-{{users_base}}-{{fl}}-{{user}}-htpasswd":
  webutil.user_exists:
    - name: "{{user}}"
    - password: "{{http_users[user]}}"
    - htpasswd_file: "{{fl}}"
    - options: m
    - force: true
    - watch:
      - file: "{{cfg.name}}-{{users_base}}-htpasswd"
{% endfor %}
{% endfor %}
