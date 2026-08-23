import org.gradle.api.tasks.bundling.Compression
import org.gradle.api.tasks.bundling.Tar

plugins {
    base
}

val clusterRelease = tasks.register<Tar>("clusterRelease") {
    group = "distribution"
    description = "Packages manager-only Docker Swarm release files."

    archiveFileName.set("cluster-release.tar.gz")
    compression = Compression.GZIP
    isPreserveFileTimestamps = false
    isReproducibleFileOrder = true

    from("apps/stacks") {
        into("stacks")
    }
    from("apps/configs") {
        into("configs")
    }
    from("apps/tools") {
        into("tools")
        filePermissions {
            user {
                read = true
                write = true
                execute = true
            }
            group {
                read = true
                execute = true
            }
            other {
                read = true
                execute = true
            }
        }
    }
}
