#!/bin/bash

ansible "*" -i $PWD/hosts -m shell -a "cd $exe_path && bash -c ${script_cmd}" -b

if [ $? -ne 0 ]; then
    echo "Backup process occurred error return..."
    echo "Send mail notification for backup failure announcement."
    git clone $TOOLS_PROJECT
    sh tool-gitlab-deployment/pipeline_mail.sh
    exit 1
fi

