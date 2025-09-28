#!/bin/bash

docker secret rm jwt_secret_code
echo "op://Private/SG App secrets/jwt_secret_code" | docker secret create jwt_secret_code -

docker secret rm sendgrid_api_key
echo "op://Private/SG App secrets/sendgrid_api_key" | docker secret create sendgrid_api_key -

docker secret rm nordigen_secret_id
echo "op://Private/SG App secrets/nordigen_secret_id" | docker secret create nordigen_secret_id -

docker secret rm nordigen_secret_key
echo "op://Private/SG App secrets/nordigen_secret_key" | docker secret create nordigen_secret_key -

docker secret rm go_cardless_secret_id
echo "op://Private/SG App secrets/go_cardless_secret_id" | docker secret create go_cardless_secret_id -

docker secret rm go_cardless_secret_key
echo "op://Private/SG App secrets/go_cardless_secret_key" | docker secret create go_cardless_secret_key -

docker secret rm postgres_password
echo "op://Private/SG App secrets/postgres_password" | docker secret create postgres_password`` -

docker secret rm accountant_db_password
echo "op://Private/SG App secrets/accountant_db_password" | docker secret create accountant_db_password`` -

docker secret rm banks_db_password
echo "op://Private/SG App secrets/banks_db_password" | docker secret create banks_db_password`` -

docker secret rm smart_home_db_password
echo "op://Private/SG App secrets/smart_home_db_password" | docker secret create smart_home_db_password -

docker secret rm tapo_user
echo "op://Private/SG App secrets/tapo_user" | docker secret create tapo_user -

docker secret rm tapo_password
echo "op://Private/SG App secrets/tapo_password" | docker secret create tapo_password -

docker secret rm tapo_device_ip
echo "op://Private/SG App secrets/tapo_device_ip" | docker secret create tapo_device_ip -

docker secret rm pjm_downloader_aws_access_key_id
echo "op://Private/SG App secrets/pjm_downloader_aws_access_key_id" | docker secret create pjm_downloader_aws_access_key_id -

docker secret rm pjm_downloader_aws_secret_access_key
echo "op://Private/SG App secrets/pjm_downloader_aws_secret_access_key" | docker secret create pjm_downloader_aws_secret_access_key -

docker secret rm intellectual_property_s3_aws_access_key_id
echo "op://Private/SG App secrets/intellectual_property_s3_aws_access_key_id" | docker secret create intellectual_property_s3_aws_access_key_id -

docker secret rm intellectual_property_s3_aws_secret_access_key
echo "op://Private/SG App secrets/intellectual_property_s3_aws_secret_access_key" | docker secret create intellectual_property_s3_aws_secret_access_key -

docker secret rm sns-client-access-key-id
echo "op://Private/SG App secrets/sns-client-access-key-id" | docker secret create sns-client-access-key-id -

docker secret rm sns-client-access-key
echo "op://Private/SG App secrets/sns-client-access-key" | docker secret create sns-client-access-key -

docker secret rm aws_region
echo "op://Private/SG App secrets/aws_region" | docker secret create aws_region -

docker secret rm aws_pjm_lambda_function
echo "op://Private/SG App secrets/aws_pjm_lambda_function" | docker secret create aws_pjm_lambda_function -

docker secret rm aws_pjm_sns_topic_arn
echo "op://Private/SG App secrets/aws_pjm_sns_topic_arn" | docker secret create aws_pjm_sns_topic_arn -

docker secret rm random_org_api_key
echo "op://Private/SG App secrets/random_org_api_key" | docker secret create random_org_api_key -

docker secret rm mysql_root_password
echo "op://Private/SG App secrets/mysql_root_password" | docker secret create mysql_root_password -

docker secret rm mysql_wordpress_password
echo "op://Private/SG App secrets/mysql_wordpress_password" | docker secret create mysql_wordpress_password -