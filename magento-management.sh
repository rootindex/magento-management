#!/usr/bin/env bash

ESC_SEQ="\x1b["

C_RESET=$ESC_SEQ"39;49;00m"
C_ERROR=$ESC_SEQ"31;01m"
C_SUCCESS=$ESC_SEQ"32;01m"
C_INFO=$ESC_SEQ"33;01m"

shopt -s nullglob
set -e


create_menu()
{
  declare -a projects

  for prj in ${working_script_path}/conf/*.conf; do
        projects[${#projects[@]}+1]=$(echo "$prj");
  done

  projects[${#projects[@]}+1]=$(echo -e "${C_INFO}Quit${C_RESET} without processing anything");

  local project_name="Unknown"
  local arrsize=${#projects[@]}

  echo -e "${C_SUCCESS}Magento Manager${C_RESET} :: Please select project configuration";
  select option in "${projects[@]}"; do

    if [ "${#projects[@]}" -eq "$REPLY" ] ;
    then
      echo -e "Bye";
      exit 0;
    fi

    if [ 1 -le "$REPLY" ] && [ "$REPLY" -le "$arrsize" ]
    then
        source "$option";
        echo -e "${C_SUCCESS}${project_name}${C_RESET} loaded project configuration: ${option}"
      break;
    else
      echo -e "${C_ERROR}Magento Manager${C_RESET} :: Incorrect Input: Select a number 1-${arrsize}"
    fi
  done
  return 0;
}

git_sub_process(){

    if [ ${git_update} = true ]; then
         echo -e "${C_SUCCESS}Git${C_RESET} :: fetch & checkout.";
         sudo -u ${server_username} git -C ${magento_root} fetch origin ${git_branch}
         sudo -u ${server_username} git -C ${magento_root} checkout ${git_branch}
         if [ ${git_submodule_update} = true ]; then
            echo -e "${C_SUCCESS}Git${C_RESET} :: submodule init, sync & update.";
            sudo -u ${server_username} git -C ${magento_root} submodule init
            sudo -u ${server_username} git -C ${magento_root} submodule sync
            sudo -u ${server_username} git -C ${magento_root} submodule update
         fi;
    else
        echo -e "${C_INFO}Git${C_RESET} :: Not enabled.";
    fi
}

magento_exists(){
    # make sure magento directory exists
    [ ! -d ${magento_root} ] || [ -z ${magento_root} ] && ( echo -e "${C_ERROR}Magento${C_RESET} :: Project does not exist"; exit 1; )

    # binary is executable
    if [ ! -x "${magento_root}/bin/magento" ]; then
        echo -e "${C_ERROR}Magento${C_RESET} :: Binary permissions problem" \
        "please run \$ ${C_INFO}chmod +x ${magento_root}/bin/magento${C_RESET}";
        exit 1;
    fi
    return 0;
}

check_user_permissions()
{
    if ! [ $(id -u) = 0 ]; then
        echo -e "${C_ERROR}Permissions Issue${C_RESET} :: please run \$ sudo $0"
        exit 1
    fi
    return 0;
}

composer_sub_process()
{
   if [ ${composer_enable} = true ]; then
         echo -e "${C_SUCCESS}Composer${C_RESET} :: Using ${composer_strategy} deployment strategy.";
         composer=$(which composer);

         if [ -f "${composer}" ]; then
            if [ -x "${composer}" ]; then
                sudo -u ${server_username} ${php_bin} ${composer} ${composer_strategy} --prefer-dist -d ${magento_root};
            else
                echo -e "${C_INFO}Composer${C_RESET} :: ${composer} does not have execute permission.";
            fi;
         else
            echo -e "${C_INFO}Composer${C_RESET} :: file not found ${composer}.";
         fi;
    else
        echo -e "${C_INFO}Composer${C_RESET} :: Not enabled.";
    fi
    return 0;
}

magento_sub_process(){
    ## Lets run this first to ensure integrity
    local user_id = $(id -u ${server_username});
    local group_id = $(id -g ${server_username});

    if [ ${m2_static_content_tmpfs} = true ]; then

        if mountpoint -q ${magento_root}/pub; then
            echo -e "${C_SUCCESS}OS${C_RESET} :: Mount /pub exists and is ready!";
        else
            echo -e "${C_INFO}OS${C_INFO} :: Mount /pub does not exist, creating it!";
            sudo -u ${server_username} cp -R ${magento_root}/pub ${magento_root}/.pub;
            mount -t tmpfs -o size=${m2_static_content_tmpfs_size},umask=0775,gid=${user_id},uid=${group_id} tmpfs ${magento_root}/pub;
            chown ${server_username}:${server_username} ${magento_root}/pub
            sudo -u ${server_username} cp -R ${magento_root}/.pub/* ${magento_root}/pub/;
            sudo -u ${server_username} rm -rf ${magento_root}/.pub;
            echo -e "${C_INFO}OS${C_RESET} :: Mount /pub Created!";
        fi
    fi;

    if [ ${m2_clear_cache} = true ]; then
        echo -e "${C_SUCCESS}Magento Manager${C_RESET} :: Flushing all caches!";
        sudo -u ${server_username} ${php_bin} ${magento_root}/bin/magento cache:flush;
        sudo -u ${server_username} rm -rf ${magento_root}/var/cache
        sudo -u ${server_username} rm -rf ${magento_root}/var/generation
        sudo -u ${server_username} rm -rf ${magento_root}/view_preprocessed
        sudo -u ${server_username} rm -rf ${magento_root}/page_cache
        sudo -u ${server_username} rm -rf ${magento_root}/static/frontend
        sudo -u ${server_username} rm -rf ${magento_root}/static/backend
    fi;

    if [ ${m2_compile_code} = true ]; then
        echo -e "${C_SUCCESS}Magento Manager${C_RESET} :: Generates DI!";
        sudo -u ${server_username} ${php_bin} ${magento_root}/bin/magento setup:di:compile;
    fi;

    if [ ${m2_compile_code_all} = true ]; then
        echo -e "${C_SUCCESS}Magento Manager${C_RESET} :: Generates DI Multi-tenant!";
        sudo -u ${server_username} ${php_bin} ${magento_root}/bin/magento setup:di:compile-multi-tenant;
    fi;

    if [ ${m2_deploy_static_content} = true ]; then
        echo -e "${C_SUCCESS}Magento Manager${C_RESET} :: Deploying static content!";
        sudo -u ${server_username} ${php_bin} ${magento_root}/bin/magento setup:static-content:deploy;
    fi;

    if [ ${m2_should_reindex} = true ]; then
        echo -e "${C_SUCCESS}Magento Manager${C_RESET} :: Running Indexer!";
        sudo -u ${server_username} ${php_bin} ${magento_root}/bin/magento indexer:reindex;
    fi;

}

restart_nginx(){
    if [ ${nginx_restart} = true ]; then
        ${nginx_initd_script} stop
        ${nginx_initd_script} start
    fi;
}

restart_phpfpm(){
    if [ ${phpfpm_restart} = true ]; then
        ${phpfpm_initd_script} stop
        ${phpfpm_initd_script} start
    fi;
}

restart_varnish(){
    if [ ${varnish_restart} = true ]; then
        ${varnish_initd_script} stop
        ${varnish_initd_script} start
    fi;
}

flush_redis_app(){
    if [ ${redis_flush_app} = true ]; then
        redis-cli -h ${redis_app_host} -p ${redis_app_port} flushall
    fi;
}

flush_redis_sessions(){
    if [ ${redis_flush_sessions} = true ]; then
        redis-cli -h ${redis_sessions_host} -p ${redis_sessions_port} flushall
    fi;
}

magento_maintenance_mode(){
    echo -e "${C_SUCCESS}Magento Manager${C_RESET} :: Setting up Maintenance Mode!";
    sudo -u ${server_username} ${php_bin} ${magento_root}/bin/magento magento maintenance:enable;
}

magento_maintenance_mode_off(){
    echo -e "${C_SUCCESS}Magento Manager${C_RESET} :: Turning off Maintenance Mode!";
    sudo -u ${server_username} ${php_bin} ${magento_root}/bin/magento magento maintenance:disable;
}

magento_management(){

    # include default vars
    [ -f "${working_script_path}/defaults.conf" ] && ( source "${working_script_path}/defaults.conf" )
    # load and shot all available projects
    create_menu;
    # make sure we have a working magento 2 copy
    # ensure magento binary exist and can be run
    magento_exists;

    # git first as it might contain updates
    git_sub_process;
    # check if we shouldn't use local php
    php_bin=$(which php);
    if [ -x "${php_binary}" ]; then
        php_bin="${php_binary}";
    fi
    # deploy code via composer
    composer_sub_process;
    # magento sub routines
    magento_sub_process;
    # restart nginx if configured
    restart_nginx;
    # restart php-fpm if configured
    restart_phpfpm;
    # restart varnish if configured
    restart_varnish;
    # flush redis if required
    flush_redis_app;
    flush_redis_sessions;

    # all done lets exit
    echo -e "${C_SUCCESS}Magento Manager${C_RESET} :: All scripts has been processed!";
    return 0;
}

# set working path
working_script_path="$(dirname "$(test -L "$0" && readlink "$0" || echo "$0")")"
# make sure we execute as correct user
check_user_permissions;
# lets execute the full program
magento_management;
# clean exit
exit 0;