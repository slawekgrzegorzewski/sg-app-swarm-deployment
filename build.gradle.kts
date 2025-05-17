import java.nio.file.Paths

plugins {
    id("jvm-test-suite")
}

val infrastructure = tasks.register<Zip>("infrastructure") {
    archiveFileName.set("infrastructure.zip")
    from("apps/common/setup") {
        include("setup_directories.sh")
    }
    from("infrastructure/") {
        include("cloud_watch_config.json")
        include("setup.sh")
    }
}

val dockerPackage = tasks.register<Zip>("dockerPackage") {
    archiveFileName.set("docker.zip")
    from("apps/common") {
        include("management/*")
        include("setup/*")
        into("core")
    }
    from("apps/core") {
        include("management/*")
        include("setup/*")
        include("stack/*")
        include("stack/config/*")
        exclude("stack/README.md")
        into("core")
    }
    from("apps/common") {
        include("management/*")
        include("setup/*")
        into("db")
    }
    from("apps/db") {
        include("management/*")
        include("setup/*")
        include("stack/*")
        into("db")
    }
    from("apps/common") {
        include("management/*")
        include("setup/*")
        into("sg-application")
    }
    from("apps/sg-application") {
        include("management/*")
        include("setup/*")
        include("stack/*")
        include("stack/config/*")
        exclude("Dockerfile*")
        into("sg-application")
    }
    from("apps/infrastructure") {
        include("management/*")
        include("setup/*")
        into("infrastructure")
    }
}

tasks.register("generate-secrets") {
    val generatedDir = project.layout.buildDirectory.dir("generated/secrets/accountant").get().asFile
    val certsDir = generatedDir.resolve("certs")
    val sourceDir = file(
        Paths.get(
            "apps", "sg-application", "secrets"
        )
    )
    doFirst {
        generatedDir.deleteRecursively()
        certsDir.mkdirs()
    }
    doLast {
        arrayOf("setup_secrets.sh", "put_secrets_to_env.sh", "clear_secrets_from_env.sh").forEach {
            exec {
                commandLine(
                    "op", "inject",
                    "-i", sourceDir.resolve(it).path,
                    "-o", generatedDir.resolve(it).path
                )
            }
        }
        arrayOf("htpasswd", "id_rsa", "id.pub").forEach {
            exec {
                commandLine(
                    "op", "read", "op://Private/SG App secrets/" + it, "-o", generatedDir.resolve(it).path, "-f"
                )
            }
        }
        arrayOf("sgapplication.key", "sgapplication.crt").forEach {
            exec {
                commandLine(
                    "op", "read", "op://Private/SG App secrets/" + it, "-o", certsDir.resolve(it).path, "-f"
                )
            }
        }
    }
}