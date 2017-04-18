---
title: Free HTTPS on AWS Elastic Beanstalk without Load Balancer
date: 2017-04-15 22:19:07
tags: AWS, Elastic, Beanstalk, Load Balancing, SSL, TLS, certificate, LetsEncrypt, nginx, Multi-container, Docker, free
intro: Setup free LetsEncrypt SSL/TLS certificate with just a Dockerrun.aws.json file on a single EC2 instance Multi-container Docker Elastic Beanstalk environment without a load balancer. Bundled with HTTP to HTTPS redirect out of the box.
---

AWS offers free SSL certificates but they are to be used [only](https://aws.amazon.com/certificate-manager/) on a load balancer or a CloudFront distribution. The latter is a CDN solution for static websites and cannot be used to host a backend app.

A load balancer offers some really good [perks](https://aws.amazon.com/elasticloadbalancing/) besides splitting traffic. For example, it lets you monitor number of requests in a convenient way, which you can't do as easily on an EC2 instance.

But if all you need from a load balancer is an SSL certificate, you can save minimum [$18 per month](https://aws.amazon.com/elasticloadbalancing/classicloadbalancer/pricing/) by following the steps below.

> You can find a working example [here](https://github.com/vfeskov/war-of-bob).

### Dockerize your app and push

For this particular method to work you will need to [dockerize](https://docs.docker.com/engine/examples/) your application. Make sure you expose a single port in your Dockerfile by adding, for example, `EXPOSE 3000` line at the end. If you expose multiple ports then nginx will default to port `80`.

Build and push the image to either private or public Docker repository. If you choose a public repo, make sure you don't push your secrets with the image. A good way to avoid it, and this method actually requires it, is to use environment variables to store secrets.

### Create Dockerrun.aws.json

Replace `<<<<<<<<<something something>>>>>>>>>` with actual values in the following code snippet, save it as `Dockerrun.aws.json` and compress it.

> If the docker image of your app is published in a private repo, make sure to include [authentication config](http://docs.aws.amazon.com/elasticbeanstalk/latest/dg/create_deploy_docker_v2config.html#docker-multicontainer-dockerrun-privaterepo) to the file.

``` json
{
  "AWSEBDockerrunVersion": 2,
  "volumes": [
    {
      "name": "home-ec2-user-certs",
      "host": {
        "sourcePath": "/home/ec2-user/certs"
      }
    },
    {
      "name": "etc-nginx-vhost-d",
      "host": {
        "sourcePath": "/etc/nginx/vhost.d"
      }
    },
    {
      "name": "usr-share-nginx-html",
      "host": {
        "sourcePath": "/usr/share/nginx/html"
      }
    },
    {
      "name": "var-run-docker-sock",
      "host": {
        "sourcePath": "/var/run/docker.sock"
      }
    }
  ],
  "containerDefinitions": [
    {
      "name": "nginx-proxy",
      "image": "jwilder/nginx-proxy",
      "essential": true,
      "memoryReservation": 128,
      "dockerLabels": {
        "com.github.jrcs.letsencrypt_nginx_proxy_companion.nginx_proxy": "true"
      },
      "portMappings": [
        {
          "containerPort": 80,
          "hostPort": 80
        },
        {
          "containerPort": 443,
          "hostPort": 443
        }
      ],
      "mountPoints": [
        {
          "sourceVolume": "home-ec2-user-certs",
          "containerPath": "/etc/nginx/certs",
          "readOnly": true
        },
        {
          "sourceVolume": "etc-nginx-vhost-d",
          "containerPath": "/etc/nginx/vhost.d"
        },
        {
          "sourceVolume": "usr-share-nginx-html",
          "containerPath": "/usr/share/nginx/html"
        },
        {
          "sourceVolume": "var-run-docker-sock",
          "containerPath": "/tmp/docker.sock",
          "readOnly": true
        }
      ]
    },
    {
      "name": "letsencrypt-nginx-proxy-companion",
      "image": "jrcs/letsencrypt-nginx-proxy-companion",
      "essential": true,
      "memoryReservation": 128,
      "volumesFrom": [
        {
          "sourceContainer": "nginx-proxy"
        }
      ],
      "mountPoints": [
        {
          "sourceVolume": "home-ec2-user-certs",
          "containerPath": "/etc/nginx/certs"
        },
        {
          "sourceVolume": "var-run-docker-sock",
          "containerPath": "/var/run/docker.sock",
          "readOnly": true
        }
      ]
    },
    {
      "name": "app",
      "image": "<<<<<<<<<YOUR PUBLISHED DOCKER IMAGE>>>>>>>>>",
      "essential": true,
      "memoryReservation": 256,
      "environment": [
        {
          "name": "VIRTUAL_HOST",
          "value": "<<<<<<<<<YOUR APP'S HOST>>>>>>>>>"
        },
        {
          "name": "LETSENCRYPT_HOST",
          "value": "<<<<<<<<<YOUR APP'S HOST>>>>>>>>>"
        },
        {
          "name": "LETSENCRYPT_EMAIL",
          "value": "<<<<<<<<<YOUR EMAIL HERE>>>>>>>>>"
        }
      ]
    }
  ]
}
```

You should end up with a `*.zip` file with `Dockerrun.aws.json` inside.

### Create Elastic Beanstalk app and environment

Create an Elastic Beanstalk application, all it will ask is a name. Next create an environment under it:
1. Choose `Web server environment`.
2. Choose `Preconfigured platform`: `Multi-container Docker`.
3. Choose `Upload your code`, click `Upload` and select the `*.zip` file you made in the previous step.
4. Click `Configure more options`.
5. (Optional) Under `Environment settings` click `Modify` and rename the environment, it will be impossible later.
6. Under `Software settings` click `Modify`. Add all the environment variables your app needs under `Environment properties`.
7. Click `Create environment`.
8. Environment will stabilise in about 10 minutes.
> NOTE: The first time this container is launched it generates a new Diffie-Hellman group file. This process can take several minutes to complete (be patient).
> - [README docker-letsencrypt-nginx-proxy-companion](https://github.com/JrCs/docker-letsencrypt-nginx-proxy-companion)

### Allow HTTPS port on EC2 Instance

1. Find and select an EC2 instance with the same name as the environment you created.
2. In `Description` of the instance click on the name next to `Security group`.
3. Select `Inbound` tab of the security group info.
4. Click `Edit`.
5. Click `Add rule`, choose `Type`: `HTTPS`.
6. Click: `Save`.

### Point the (sub)domain of your app to your Elastic Beanstalk environment

If you're hosting DNS of your domain on AWS Route53:
1. Select the appropriate Hosted Zone.
2. If you don't have an A record for the app's (sub)domain, click `Create Record Set` and choose `Type`: `A - IPv4 address`.
3. Otherwise click on the A record for the app's (sub)domain.
4. Find and select your Elastic Beanstalk environment URL in the `Alias Target` field.
5. Click `Save record set`.

If you're using another DNS provider, you should create an A record there and point it to the IP address of the created EC2 instance.

### Go to the (sub)domain of your app

The first time you access, a new [LetsEncrypt](https://letsencrypt.org/) certificate will be generated. If enough time has passed since the environment creation, your app should be up and running.

### Important to know

LetsEncrypt has [rate limits](https://letsencrypt.org/docs/rate-limits/) which you might bump up against if you recreate instance too many times. You don't have to worry about limits if you're just deploying new versions of your application.

The certificate is renewed automatically by the [docker-letsencrypt-nginx-proxy-companion](https://github.com/JrCs/docker-letsencrypt-nginx-proxy-companion#automatic-certificate-renewal) container.

### Conclusion

If you don't need a loadbalancer for anything but HTTPS, you can use a Multi-container Docker EB environment to set it up on a single instance.

### Credits

All the heavy lifting was done here: [https://github.com/JrCs/docker-letsencrypt-nginx-proxy-companion](https://github.com/JrCs/docker-letsencrypt-nginx-proxy-companion) and here: [https://github.com/jwilder/nginx-proxy](https://github.com/jwilder/nginx-proxy), kudos to them!

