#!/bin/bash

# exit immediately on failure, or if an undefined variable is used
set -eu

# our repository in AWS
repository=823773083436.dkr.ecr.us-east-1.amazonaws.com/buildkite

# list of all the tests
tests=( \
       test-cpu-openmpi-py2_7-tf1_1_0-keras2_0_0-torch0_4_0-mxnet1_4_0-pyspark2_1_2 \
       test-cpu-openmpi-py3_5-tf1_1_0-keras2_0_0-torch0_4_0-mxnet1_4_0-pyspark2_1_2 \
       test-cpu-openmpi-py3_6-tf1_1_0-keras2_0_0-torch0_4_0-mxnet1_4_0-pyspark2_1_2 \
       test-cpu-openmpi-py2_7-tf1_6_0-keras2_1_2-torch0_4_1-mxnet1_4_0-pyspark2_3_2 \
       test-cpu-openmpi-py3_5-tf1_6_0-keras2_1_2-torch0_4_1-mxnet1_4_0-pyspark2_3_2 \
       test-cpu-openmpi-py3_6-tf1_6_0-keras2_1_2-torch0_4_1-mxnet1_4_0-pyspark2_3_2 \
       test-cpu-openmpi-py2_7-tf1_12_0-keras2_2_2-torch1_0_0-mxnet1_4_0-pyspark2_4_0 \
       test-cpu-openmpi-py3_5-tf1_12_0-keras2_2_2-torch1_0_0-mxnet1_4_0-pyspark2_4_0 \
       test-cpu-openmpi-py3_6-tf1_12_0-keras2_2_2-torch1_0_0-mxnet1_4_0-pyspark2_4_0 \
       test-cpu-openmpi-py2_7-tfhead-kerashead-torchhead-mxnet1_4_0-pyspark2_4_0 \
       test-cpu-openmpi-py3_6-tfhead-kerashead-torchhead-mxnet1_4_0-pyspark2_4_0 \
       test-cpu-mpich-py2_7-tf1_12_0-keras2_2_2-torch1_0_0-mxnet1_4_0-pyspark2_4_0 \
       test-gpu-openmpi-py2_7-tf1_6_0-keras2_1_2-torch0_4_1-mxnet1_4_0-pyspark2_3_2 \
       test-gpu-openmpi-py3_5-tf1_6_0-keras2_1_2-torch0_4_1-mxnet1_4_0-pyspark2_3_2 \
       test-gpu-openmpi-py2_7-tf1_12_0-keras2_2_2-torch1_0_0-mxnet1_4_0-pyspark2_4_0 \
       test-gpu-openmpi-py3_5-tf1_12_0-keras2_2_2-torch1_0_0-mxnet1_4_0-pyspark2_4_0 \
       test-gpu-openmpi-py2_7-tfhead-kerashead-torchhead-mxnet1_4_0-pyspark2_4_0 \
       test-gpu-openmpi-py3_6-tfhead-kerashead-torchhead-mxnet1_4_0-pyspark2_4_0 \
       test-gpu-mpich-py2_7-tf1_12_0-keras2_2_2-torch1_0_0-mxnet1_4_0-pyspark2_4_0 \
       test-mixed-openmpi-py2_7-tf1_12_0-keras2_2_2-torch1_0_0-mxnet1_4_0-pyspark2_4_0 \
)

build_test() {
  local test=$1

  echo "- label: ':docker: Build ${test}'"
  echo "  plugins:"
  echo "  - docker-compose#6b0df8a98ff97f42f4944dbb745b5b8cbf04b78c:"
  echo "      build: ${test}"
  echo "      image-repository: ${repository}"
  echo "      cache-from: ${test}:${repository}:${BUILDKITE_PIPELINE_SLUG}-${test}-latest"
  echo "      config: docker-compose.test.yml"
  echo "      push-retries: 5"
  echo "  - ecr#v1.2.0:"
  echo "      login: true"
  echo "  timeout_in_minutes: 30"
  echo "  retry:"
  echo "    automatic: true"
  echo "  agents:"
  echo "    queue: cpu"
}

cache_test() {
  local test=$1

  echo "- label: ':docker: Update ${BUILDKITE_PIPELINE_SLUG}-${test}-latest'"
  echo "  plugins:"
  echo "  - docker-compose#v2.6.0:"
  echo "      push: ${test}:${repository}:${BUILDKITE_PIPELINE_SLUG}-${test}-latest"
  echo "      config: docker-compose.test.yml"
  echo "      push-retries: 3"
  echo "  - ecr#v1.2.0:"
  echo "      login: true"
  echo "  timeout_in_minutes: 5"
  echo "  retry:"
  echo "    automatic: true"
  echo "  agents:"
  echo "    queue: cpu"
}

run_test() {
  local test=$1
  local queue=$2
  local label=$3
  local command=$4

  echo "- label: '${label}'"
  echo "  command: '${command}'"
  echo "  plugins:"
  echo "  - docker-compose#v2.6.0:"
  echo "      run: ${test}"
  echo "      config: docker-compose.test.yml"
  echo "      pull-retries: 3"
  echo "  - ecr#v1.2.0:"
  echo "      login: true"
  echo "  timeout_in_minutes: 5"
  echo "  retry:"
  echo "    automatic: true"
  echo "  agents:"
  echo "    queue: ${queue}"
}

# begin the pipeline.yml file
echo "steps:"

# build every test container
for test in ${tests[@]}; do
  build_test "${test}"
done

# wait for all builds to finish
echo "- wait"

# cache test containers if built from master
if [[ "${BUILDKITE_BRANCH}" == "master" ]]; then
  for test in ${tests[@]}; do
    cache_test "${test}"
  done
fi

# run all the tests
for test in ${tests[@]}; do
  if [[ ${test} == *-cpu-* ]]; then
    queue=cpu
  else
    queue=gpu
  fi

  # convenience templates
  if [[ ${queue} == "gpu" ]]; then
    SET_CUDA_VISIBLE_DEVICES="CUDA_VISIBLE_DEVICES=\$(if [[ \\\${BUILDKITE_AGENT_NAME} == *\\\"-1\\\" ]]; then echo \\\"0,1,2,3\\\"; else echo \\\"4,5,6,7\\\"; fi)"
  else
    SET_CUDA_VISIBLE_DEVICES=""
  fi
  MPIRUN_COMMAND="\$(cat /mpirun_command)"

  run_test "${test}" "${queue}" \
    ":pytest: Run PyTests (${test})" \
    "bash -c \"cd /horovod/test && (echo test_*.py | ${SET_CUDA_VISIBLE_DEVICES} xargs -n 1 ${MPIRUN_COMMAND} pytest -v --capture=no)\""

  run_test "${test}" "${queue}" \
    ":muscle: Test TensorFlow MNIST (${test})" \
    "bash -c \"${SET_CUDA_VISIBLE_DEVICES} ${MPIRUN_COMMAND} python /horovod/examples/tensorflow_mnist.py\""

  if [[ ${test} != *"tf1_1_0"* && ${test} != *"tf1_6_0"* ]]; then
    run_test "${test}" "${queue}" \
      ":muscle: Test TensorFlow Eager MNIST (${test})" \
      "bash -c \"${SET_CUDA_VISIBLE_DEVICES} ${MPIRUN_COMMAND} python /horovod/examples/tensorflow_mnist_eager.py\""
  fi

  run_test "${test}" "${queue}" \
    ":muscle: Test Keras MNIST (${test})" \
    "bash -c \"${SET_CUDA_VISIBLE_DEVICES} ${MPIRUN_COMMAND} python /horovod/examples/keras_mnist_advanced.py\""

  run_test "${test}" "${queue}" \
    ":muscle: Test PyTorch MNIST (${test})" \
    "bash -c \"${SET_CUDA_VISIBLE_DEVICES} ${MPIRUN_COMMAND} python /horovod/examples/pytorch_mnist.py\""

  run_test "${test}" "${queue}" \
    ":muscle: Test MXNet MNIST (${test})" \
    "bash -c \"OMP_NUM_THREADS=1 ${SET_CUDA_VISIBLE_DEVICES} ${MPIRUN_COMMAND} python /horovod/examples/mxnet_mnist.py\""

  run_test "${test}" "${queue}" \
    ":muscle: Test Stall (${test})" \
    "bash -c \"${SET_CUDA_VISIBLE_DEVICES} ${MPIRUN_COMMAND} python /horovod/test/test_stall.py\""

  if [[ ${test} == *"openmpi"* ]]; then
    run_test "${test}" "${queue}" \
      ":muscle: Test Horovodrun (${test})" \
      "bash -c \"${SET_CUDA_VISIBLE_DEVICES} horovodrun -np 2 -H localhost:2 python /horovod/examples/tensorflow_mnist.py\""
  fi
done
