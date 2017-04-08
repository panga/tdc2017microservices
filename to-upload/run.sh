#!/bin/bash

set -eu

# Load Weave defaults
WEAVE_CLI=/usr/local/bin/weave
source /etc/default/weave
export WEAVE_MTU

is_container_running() {
    [ "$(docker inspect -f '{{.State.Running}}' $1 2> /dev/null)" = true ]
}

succeed_or_die() {
    if ! OUT=$("$@" 2>&1); then
	  echo "error: '$@' failed: $OUT"
	  exit 1
    fi
    echo $OUT
}

run_scope() {
    while true; do
	# verify that scope is not running
	while is_container_running weavescope; do sleep 2; done

	# launch scope
	ARGS="--probe.ecs=true"
	if [ -e /etc/weave/scope.config ]; then
	    . /etc/weave/scope.config
	fi
	if [ -n "${SERVICE_TOKEN+x}" ]; then
	    ARGS="$ARGS --service-token=$SERVICE_TOKEN"
	fi
	succeed_or_die scope launch $ARGS
    done
}

run_weave() {
  # Ideally we would use a pre-stop Upstart stanza for terminating Weave, but we can't
  # because it would cause ECS to stop in an unorderly manner:
  #
  # Stop Weave -> Weave pre-stop stanza -> Weave stopping event -> ECS pre-stop ...
  #  
  # The Weave pre-stop stanza would kick in before stopping ECS, which would result in
  # the ECS Upstart job supervisor dying early (it talks to the weave proxy,
  # which is gone), not allowing the ECS pre-stop stanza to kick in and stop the
  # ecs-agent
  trap 'succeed_or_die weave stop; exit 0' TERM
  while true; do
      # verify that weave is not running
      while is_container_running weaveproxy && is_container_running weave; do sleep 2; done
      # launch weave
      if ! is_container_running weave; then
        PEERS=$(succeed_or_die /etc/weave/peers.sh | tr "\n" " ")
	    succeed_or_die $WEAVE_CLI launch-router --no-dns --ipalloc-range $CIDR $PEERS
	    succeed_or_die $WEAVE_CLI expose
      fi
      if ! is_container_running weaveproxy; then
	    succeed_or_die $WEAVE_CLI launch-proxy --rewrite-inspect --without-dns --hostname-from-label 'com.amazonaws.ecs.container-name'
      fi
  done
}

run_weave