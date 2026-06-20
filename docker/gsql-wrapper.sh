#!/bin/bash
exec gsql -d pagila -U gaussdb -W "Enmo@123" "$@"
