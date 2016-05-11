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

magento_root_exists(){
    # make sure magento directory exists
    [ ! -d ${magento_root} ] || [ -z ${magento_root} ] && ( echo -e "${C_ERROR}Magento${C_RESET} :: Project does not exist"; exit 1; )
    return 0;
}

magento_binary_xst(){
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

magento_clear_cache(){
    if [ ${m2_clear_cache} = true ]; then
        echo -e "${C_SUCCESS}Magento Manager${C_RESET} :: Flushing all caches!";
        sudo -u ${server_username} ${php_bin} ${magento_root}/bin/magento cache:flush;
    fi;
}

magento_compile_di()
{
    if [ ${m2_compile_code} = true ]; then
        echo -e "${C_SUCCESS}Magento Manager${C_RESET} :: Generates DI!";
        sudo -u ${server_username} ${php_bin} ${magento_root}/bin/magento setup:di:compile;
    fi;
}

magento_compile_di_all()
{
    if [ ${m2_compile_code_all} = true ]; then
        echo -e "${C_SUCCESS}Magento Manager${C_RESET} :: Generates DI Multi-tenant!";
        sudo -u ${server_username} ${php_bin} ${magento_root}/bin/magento setup:di:compile-multi-tenant;
    fi;
}

magento_deploy_static_content()
{
    if [ ${m2_deploy_static_content} = true ]; then
        echo -e "${C_SUCCESS}Magento Manager${C_RESET} :: Deploying static content!";
        sudo -u ${server_username} ${php_bin} ${magento_root}/bin/magento setup:static-content:deploy;
    fi;
}

magento_static_content_tmpfs()
{
    if [ ${m2_static_content_tmpfs} = true ]; then
        echo mount -o tmpfs
    fi;
}

magento_management(){
    # include default vars
    [ -f "${working_script_path}/defaults.conf" ] && ( source "${working_script_path}/defaults.conf" )
    # load and shot all available projects
    create_menu;
    # make sure we have a working magento 2 copy
    magento_root_exists;
    # ensure magento binary exist and can be run
    magento_binary_xst;
    # git first as it might contain updates
    git_sub_process;

    # check if we shouldn't use local php
    php_bin=$(which php);
    if [ -x "${php_binary}" ]; then
        php_bin="${php_binary}";
    fi

    # deploy code via composer
    composer_sub_process;

    # clear caches
    magento_clear_cache;
    magento_compile_di;
    magento_compile_di_all;
    magento_deploy_static_content;
    magento_static_content_tmpfs;


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