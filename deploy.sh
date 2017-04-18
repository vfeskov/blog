#!/bin/bash
hexo generate && \
aws s3 cp --recursive --acl public-read public s3://$S3_BUCKET/ &&
aws cloudfront create-invalidation --distribution-id $CLOUDFRONT_ID --paths "/*" "/"
