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
echo "op://Private/SG App secrets/postgres_password" | docker secret create postgres_password -

docker secret rm aws_access_key_id
echo "op://Private/SG App secrets/aws_access_key_id" | docker secret create aws_access_key_id -

docker secret rm aws_secret_access_key
echo "op://Private/SG App secrets/aws_secret_access_key" | docker secret create aws_secret_access_key -

docker secret rm intellectual_property_s3_aws_access_key_id
echo "op://Private/SG App secrets/intellectual_property_s3_aws_access_key_id" | docker secret create intellectual_property_s3_aws_access_key_id -

docker secret rm intellectual_property_s3_aws_access_key
echo "op://Private/SG App secrets/intellectual_property_s3_aws_access_key" | docker secret create intellectual_property_s3_aws_access_key -

docker secret rm aws_region
echo "op://Private/SG App secrets/aws_region" | docker secret create aws_region -

docker secret rm aws_pjm_lambda_function
echo "op://Private/SG App secrets/aws_pjm_lambda_function" | docker secret create aws_pjm_lambda_function -

docker secret rm random_org_api_key
echo "op://Private/SG App secrets/random_org_api_key" | docker secret create random_org_api_key -