# Releasing Dapper

How a new version gets to everyone who installs Dapper. Pushing a version
tag publishes it to GitHub, Docker and Homebrew; the CPAN upload is the one
step done by hand.

| Where | How it gets there |
|---|---|
| GitHub release (single-file `dapper`) | The release workflow, on the tag |
| Docker (`ghcr.io/markdbenson/dapper`) | The release workflow, on the tag |
| Homebrew (`markdbenson/tap/dapper`) | The release workflow, on the tag |
| CPAN (`App::Dapper`) | Uploaded by hand to PAUSE |

## Before the release

1. Set the version in `lib/App/Dapper.pm` (`our $VERSION`). It is the only
   place the version is kept.
2. Add an entry to the top of `Changes`, with the version and the date it
   will be released. A summary paragraph comes first, then one paragraph for
   each change, starting with `Added:`, `Changed:`, `Fixed:` or `Removed:`.
   This entry becomes the GitHub release notes, so check it with:

       perl packaging/release-notes.pl 1.01

3. Make sure the pull request's checks pass, then merge it into `master`.

## The release

4. Tag the merge commit and push the tag:

       git checkout master && git pull
       git tag -a v1.01 -m "Dapper 1.01"
       git push origin v1.01

   The release workflow (`.github/workflows/release.yml`) then:
   * builds the single-file `dapper` and creates the GitHub release with it,
     its checksum, and the notes from `Changes`;
   * builds and publishes the Docker image as `:1.01` and `:latest`;
   * updates `Formula/dapper.rb` in
     [markdbenson/homebrew-tap](https://github.com/markdbenson/homebrew-tap)
     to the new version and checksum.

   Check that the workflow passed on the
   [Actions page](https://github.com/markdbenson/dapper/actions/workflows/release.yml).

5. Build the CPAN file from the tagged code and test it:

       perl Makefile.PL && make dist && make disttest

   Then sign in at [PAUSE](https://pause.perl.org), choose "Upload a file to
   CPAN", and upload `App-Dapper-1.01.tar.gz`. PAUSE emails when it is
   indexed, and [MetaCPAN](https://metacpan.org/dist/App-Dapper) lists it
   soon after. Afterwards, `make clean` removes the build files.

## After the release

6. Check each place has the new version:

       brew update && brew upgrade dapper && dapper -v
       docker run --rm --platform linux/amd64 ghcr.io/markdbenson/dapper:1.01 -v

   The image is built for Intel (amd64) only, so on an Apple Silicon Mac the
   `--platform` flag is needed.

7. Copy the checksum the workflow wrote into `packaging/homebrew/dapper.rb`,
   so the copy here matches the tap:

       packaging/homebrew/update-formula.sh 1.01 > dapper.rb.new &&
           mv dapper.rb.new packaging/homebrew/dapper.rb

   (Writing straight to `dapper.rb` would empty it, since the script reads
   that file.)

8. For a larger release, tell people: a news item for the
   [Perl Weekly](https://perlweekly.com) newsletter, a post on r/perl or
   blogs.perl.org, and your own blog and social accounts. Anyone watching
   the repository on GitHub gets the release notes by email.

## Setting up the Homebrew token (once)

The release workflow needs permission to push to the tap repository. Until
it has it, the `homebrew` job prints a warning and the tap is left as it
is; run step 7's command and commit the result to the tap by hand instead.

1. On GitHub, go to Settings, Developer settings, Personal access tokens,
   [Fine-grained tokens](https://github.com/settings/personal-access-tokens/new).
2. Name it "dapper release to homebrew-tap", give it an expiration date,
   choose "Only select repositories" and pick `markdbenson/homebrew-tap`.
3. Under Repository permissions, set Contents to "Read and write".
   Generate the token and copy it.
4. In the dapper repository, go to Settings, Secrets and variables,
   [Actions](https://github.com/markdbenson/dapper/settings/secrets/actions),
   choose "New repository secret", name it `HOMEBREW_TAP_TOKEN`, and paste
   the token.

When the token expires, make a new one and replace the secret.
