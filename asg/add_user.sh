#!/bin/bash
adduser ${username}
usermod -G wheel ${username}
usermod -G docker ${username}
mkdir /home/${username}/.ssh
chmod 700 /home/${username}/.ssh/
touch /home/${username}/.ssh/authorized_keys
echo "${public_key}" >> /home/${username}/.ssh/authorized_keys
chmod 600 /home/${username}/.ssh/authorized_keys
chown -R ${username}:${username} /home/${username}/.ssh
