import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import java.io.ByteArrayOutputStream
import java.nio.file.Paths

buildscript {
    dependencies {
        classpath("org.jetbrains.kotlinx:kotlinx-serialization-json:1.9.0")
    }
}

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
        into("db_mysql")
    }
    from("apps/db_mysql") {
        include("management/*")
        include("setup/*")
        include("stack/*")
        into("db_mysql")
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
    val accountUUIDStdout = ByteArrayOutputStream()
    exec {
        commandLine(
            "op",
            "account",
            "list",
            "--format",
            "json"
        )
        standardOutput = accountUUIDStdout
    }
    val accountObject = Json.parseToJsonElement(accountUUIDStdout.toString()).jsonArray
        .filter { it.jsonObject["email"]!!.jsonPrimitive.content == "slawek.grz@gmail.com" }[0].jsonObject
    val accountUUID = accountObject["account_uuid"]!!.jsonPrimitive.content

    doFirst {
        generatedDir.deleteRecursively()
        certsDir.mkdirs()
    }
    doLast {
        arrayOf("setup_secrets.sh", "put_secrets_to_env.sh", "clear_secrets_from_env.sh").forEach {
            exec {
                commandLine(
                    "op", "inject", "--account", accountUUID,
                    "-i", sourceDir.resolve(it).path,
                    "-o", generatedDir.resolve(it).path
                )
            }
        }
        arrayOf("htpasswd", "id_rsa", "id.pub").forEach {
            exec {
                commandLine(
                    "op",
                    "read",
                    "--account",
                    accountUUID,
                    "op://Private/SG App secrets/" + it,
                    "-o",
                    generatedDir.resolve(it).path,
                    "-f"
                )
            }
        }
        arrayOf("sgapplication.key", "sgapplication.crt").forEach {
            exec {
                commandLine(
                    "op",
                    "read",
                    "--account",
                    accountUUID,
                    "op://Private/SG App secrets/" + it,
                    "-o",
                    certsDir.resolve(it).path,
                    "-f"
                )
            }
        }
    }
}