variable "APP_REVISION" {
  default = "unknown"
}

variable "RELEASE_LOCK_CHECKSUM" {
  default = "unknown"
}

variable "GIT_LOCK_CHECKSUM" {
  default = "unknown"
}

variable "LOCAL_LOCK_CHECKSUM" {
  default = "unknown"
}

group "default" {
  targets = ["release", "git", "local"]
}

target "_common" {
  context = "./sales-application"
  labels = {
    "org.opencontainers.image.source" = "https://github.com/jettro/pmps-sales-application"
  }
  output = ["type=docker"]
}

target "release" {
  inherits = ["_common"]
  dockerfile = "Dockerfile"
  tags = ["pmps-sales-application:release"]
  extra-hosts = {
    "host.docker.internal" = "host-gateway"
  }
  args = {
    SOURCE_MODE = "release"
    APP_REVISION = APP_REVISION
    LOCK_CHECKSUM = RELEASE_LOCK_CHECKSUM
  }
  secret = [
    "type=env,id=uv_index_username,env=UV_INDEX_LOCAL_USERNAME",
    "type=env,id=uv_index_password,env=UV_INDEX_LOCAL_PASSWORD",
  ]
}

target "git" {
  inherits = ["_common"]
  dockerfile = "Dockerfile"
  tags = ["pmps-sales-application:git"]
  args = {
    SOURCE_MODE = "git"
    APP_REVISION = APP_REVISION
    LOCK_CHECKSUM = GIT_LOCK_CHECKSUM
  }
}

target "local" {
  inherits = ["_common"]
  dockerfile = "Dockerfile.local"
  tags = ["pmps-sales-application:local"]
  contexts = {
    platform-core = "./platform-core"
    platform-framework = "./platform-framework"
  }
  args = {
    APP_REVISION = APP_REVISION
    LOCK_CHECKSUM = LOCAL_LOCK_CHECKSUM
  }
}
