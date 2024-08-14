plugins {
    id("jvm-test-suite")
}

val infrastructureRpi4 = tasks.register<Zip>("infrastructureRpi4") {
    archiveFileName.set("infrastructureRpi4.zip")
    from("apps/common/setup") {
        include("setup_directories.sh")
    }
    from("infrastructure/") {
        include("cloud_watch_config.json")
        include("setup.sh")
    }
}

val dockerPackageRpi4 = tasks.register<Zip>("dockerPackageRpi4") {
    archiveFileName.set("dockerRpi4.zip")
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
}