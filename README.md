# Web Editor Support For The Xtext Framework

This repository contains the [web editor support for Xtext](https://www.eclipse.org/Xtext/documentation/330_web_support.html).

## How To Build

Check out and run `./gradlew build`.

Additional command line arguments:
 - `-PuseJenkinsSnapshots=true` switches to using the Maven repositories generated by the [Jenkins build jobs](http://services.typefox.io/open-source/jenkins/) for [xtext-lib](https://github.com/eclipse/xtext-lib), [xtext-core](https://github.com/eclipse/xtext-core), and [xtext-extras](https://github.com/eclipse/xtext-extras). Without this argument, [Sonatype snapshots](https://oss.sonatype.org/content/repositories/snapshots) are used.

## Continuos Integration

This project is built by the [xtext-web multi-branch job on Jenkins](http://services.typefox.io/open-source/jenkins/job/xtext-web/).
