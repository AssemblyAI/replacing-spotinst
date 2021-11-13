#!/usr/bin/env bash

pip install -t ./ -r requirements.txt

zip -r artifact.zip . -x requirements.txt test*