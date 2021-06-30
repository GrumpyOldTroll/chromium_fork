# Overview

This repo is for maintaining a [fork of chromium](https://github.com/GrumpyOldTroll/chromium) that includes a [multicast API](/https://github.com/GrumpyOldTroll/wicg-multicast-receiver-api), and to regularly sync it from upstream.  The target is to stay up to date daily with the latest dev and stable builds, with a 1-week grace period when manual fixes are needed.

There's a set of URLS of recent builds in [CURRENT_BINARIES.stable.md](CURRENT_BINARIES.stable.md) and [CURRENT_BINARIES.dev.md](CURRENT_BINARIES.dev.md) with download links for .deb files.

To download and run it against a page that can join multicast traffic and receive payloads in javascript, you can run it like this:

~~~
VER=<pick recent value from LAST_GOOD.stable.sh or CURRENT_BINARIES>
curl -O https://jholland-vids.edgesuite.net/chromium-builds/dev/chromium-browser-mc-unstable_${VER}-1_amd64.deb
sudo dpkg --install chromium-browser-mc-unstable_${VER}-1_amd64.deb

URL="https://htmlpreview.github.io/?https://github.com/GrumpyOldTroll/wicg-multicast-receiver-api/blob/master/demo-multicast-receive-api.html"

chromium-browser-mc-unstable --enable-blink-features=MulticastTransport ${URL}
~~~

# Build Process

The automated nightly build tries applying the last known good patch on top of the current dev and stable release tags from the chromium upstream.

Whenever that fails, or whenever there's new edits to the multicast API feature, new commits get folded into the multicast API fork and the last good patch url gets updated so that future builds start hopefully working again.

# Branch and Tag Organization

## Branches:

 * [multicast-base](https://github.com/GrumpyOldTroll/chromium/tree/multicast-base) is where the baseline multicast implementation is to be developed.  This branch always merges to the [merge base](https://git-scm.com/docs/git-merge-base) commits for new release branches from the upstream.  Feature work should generally branch from here, do the dev work, rebase from this branch (in case it moved), and then merge the change into this branch, then make sure the last good url points to commits that incorporate these changes.
   * This branch should specifically avoid pulling any of the version-specific changes to DEPS or chrome/VERSION in upstream release branches (to the point that we might break history to reverse this if it happens by accident, as it seems to make rebasing very painful). In general, this is done by being careful to merge only to commits from upstream-main, not any of the commits from further down the version branches.
 * multicast-patch-\<version-base\> gets created for version branches when they have merge conflicts or build or runtime errors that need fixing on top of multicast-base in order to rebase to a release tag's commit.  Usually these fixes can be done in multicast-base instead, but sometimes they might need a branch.  These are also created for the stable branch even if there are no fixes needed because the stable release gets thousands of updates such that a rebase of a branch containing the multicast changes from the point where it branched from main to the release tag can take minutes to apply.
 * [upstream-main](https://github.com/GrumpyOldTroll/chromium/tree/upstream-main) exactly tracks the [upstream main](https://chromium.googlesource.com/chromium/src/+/refs/heads/main) branch, lagging behind by hopefully-less-than-a-week.  It should never contain anything different than the upstream main.  If it accidentally diverges for some reason, we'll break history on this branch to put it back in sync.

We don't keep a branch for tracking dev releases like we do for stable because the rebranching off main for a new dev release happens too often.  However, branching off multicast-base and rebasing to the latest dev tag from upstream is generally equivalent to what that branch would be, for the latest dev build.

## Tags

We use tags to help track the commit chains for builds we made that included the multicast API.

If we had a successful build, there should be 2 tags, one of which is shared across multiple updates for a major release branch.

 - mcbp-\<version-base\>, e.g. mcbp-89.0.4389 (note: only the first 3 numbers, not the 4 of the full version tag from chromium).  This was the commit that resulted from moving multicast-base to the merge-base commit that's common to the version branch and main (as reported by git merge-base).  "bp" in the name stands for "branch point".
 - mc-\<version\>: e.g. mc-89.0.4389.82.  This commit results from rebasing a branch starting from the corresponding mcbp-\<version-base\> tag to the commit at the release version tag.

# Manual Changes to Fix Issues

This section is a walkthrough of what to do when the automated update doesn't work.

The intent is to make this part as painless as possible since it represents the majority of instances of code changes, because merging dev work on the multicast feature code tends to be a much slower pace of individual edits at this stage.  Chromium gets a lot of commits, and some of them have merge failures with this (relatively large) feature.

(Suggestions that can improve on this process are very welcome, as it seems more complex than the ideal, but it MUST fit into a nightly automated build workflow that requires no manual intervention for the most common case of not having new conflicts for a new dev or stable version of chromium.)

Usually the need for a new edit will come from a nightly build failure on dev.  This will send an a email to the select group of champions who are holding this fork together.

The easiest way to fix it involves getting onto the build server and starting at the chromium_fork directory.

~~~
cd src/chromium_fork
~~~

(It is also generally possible to reproduce by pulling this repo and running ./nightly.sh locally, if you can't use the build server.)

Once it has failed for either dev or stable, there's 2 things left behind:

 - a docker container where the environment for the build is contained
   - this is named "cbuild-dev" or "cbuild-stable", depending on the release channel
 - a temp directory on the docker host where the fetch, checkout, patch, and build was attempted.
   - this is generated with "[mktemp](https://www.gnu.org/software/autogen/mktemp.html) -d", and the `nightly-junk/bld-dev` or `nightly-junk/bld-stable` symbolic link points to it.  On a default ubuntu install this will usually be something like /tmp/chromium-build-xxxx.  This directory gets bind-mounted into the docker container, so renaming it will prevent working inside the container, which is otherwise possible.

My preferred approach for editing the source directory is to cd into it from the host and edit files there.  Also useful is to set the remote url assuming you'll be committing to it:

~~~
cd nightly-junk/bld-dev/src
git remote set-url multicast git@github.com:GrumpyOldTroll/chromium.git
~~~

However, to actually attempt the build the easiest way is to start the container, which tries to allow an interactive build from inside:

~~~
docker start -i cbuild-dev
autoninja -c out/Default chrome
~~~

(That will be in the /bld/src directory inside the container, where /bld was bind-mounted to a /tmp/chromium-build-xxx in the host.)

Either way, there's a env.sh file stuck into `out/Default/env.sh` with some helpful variables that establish context for the build attempt:

 - VERSION: the new version we're trying to build the multicast API on top of
 - LASTGOOD: the prior version from LAST_GOOD.dev.sh (or LAST_GOOD.stable.sh).
 - CHAN: dev or stable, depending which one's being built.

Recommended in both the host and the container is to `. out/Default/env.sh` to set these variables in your shell while working, the rest of the commands will use these variables assuming they've been set.

For doing rebases you may want to set [rerere](https://git-scm.com/book/en/v2/Git-Tools-Rerere):

~~~
git config --global rerere.enabled true
~~~

## Failure Modes

### Patch Application Failure

In the most common case that needs intervention, there's an error from the git apply (usually it's from some other line that got added to the same place one of the multicast hookups added a line).

In this case, the message from the end of the log file will say the git apply failed, and the git status will show a clean directory with no edits.
Most likely you can move on to "[Building a Patch](#building-a-patch)".

You'll basically be rebasing a local dummy branch to produce a new tag that builds and runs successfully, starting from an earlier working tag.  If it's the dev branch, you'll often be rebasing the `multicast/multicast-base` branch as part of that.

(If doing that produces a build or test failure, you'd basically come back to the "Build Failure" section.)

### Build Failure

Sometimes even though there's no merge failure, headers may have changed in a way that can cause build errors for a patch that applied cleanly.

In this case it'll usually be a compile error somewhere, and the git status will show a whole pile of multicast-related local file changes.

Like the Patch Application Failure case, this will generally require checking in a change, usually to multicast-base, and then rebasing to get back to this point.

However, unlike the patch failure, in this case there might be an intermediate build that you can use to check your changes incrementally and more quickly, before trying to troubleshoot the patch, and this can save time in fixing the issue.

If you want to make local edits before beginning the rebase process to do quick checks about what it takes to fix compiling, it's strongly encouraged to capture the snapshot you're making the changes against by making a local commit to a local branch before doing anything:

~~~
git checkout -b experimental-fixing-branch
git add -A .
git commit -m "capturing the applied last good diff before trying to fix build errors"
~~~

After that, go ahead and make edits and satisfy yourself they'll fix the build errors successfully:

~~~
autoninja -C out/Default chrome
~~~

Once that's in shape, it's often helpful to capture them:

~~~
git commit -a --amend
~~~

Then proceed to the "Building a Patch" section.

#### Example

When moving to 91.0.4469.4, there was a build error on top of the merge error:

~~~
../../content/browser/multicast/multicast_receiver_manager.cc:103:17: error: no member named 'ThreadPool' in namespace 'base'
          base::ThreadPool::CreateSequencedTaskRunner({base::MayBlock(),
          ~~~~~~^
1 error generated.
~~~

This was caused by some changes in what some header files included in the upstream, and meant that we needed to change the includes for that file, but until we figure that out, it's not that clear what the issue is, and we want to make sure we know the changes that were needed.

So first we capture the current state.

Since a patch was applied on top of a specific version, this has a bunch of local changes.  Additionally, this is not a state we're going to directly check into multicast-base, since it has edits to the DEPS and chrome/VERSION files that will cause neverending merge failures if checked in.

But we still want to be able to produce a diff with a patch, so first we capture a starting point we can diff against:

~~~
cd nightly-junk/bld-dev/src
git checkout -b experimental-fixing-branch
git add -A .
git commit -m "capturing the applied last good diff before trying to fix build errors"
~~~

Then after [looking around a bit](https://source.chromium.org/chromium/chromium/src/+/0d0d0a6a7f31704ca31756711fd5081fbb35e7f5:base/task/post_task.h;dlc=087036d00637fda60604f34b080c930816f14c7a), we find a likely fix:

~~~
$ git diff
diff --git a/content/browser/multicast/multicast_receiver_manager.cc b/content/browser/multicast/multicast_receiver_manager.cc
index b8c19b39aebd..3aa6985b9532 100644
--- a/content/browser/multicast/multicast_receiver_manager.cc
+++ b/content/browser/multicast/multicast_receiver_manager.cc
@@ -5,6 +5,7 @@
 #include "content/browser/multicast/multicast_receiver_manager.h"
 
 #include "base/task/post_task.h"
+#include "base/task/thread_pool.h"
 #include "base/threading/scoped_blocking_call.h"
 #include "content/browser/multicast/multicast_receiver.h"
 #include "content/browser/multicast/multicast_generator/libmcrx_multicast_generator.h"
~~~

Going inside the container and running `autoninja -C out/Default chrome` ends up building successfully, so we move on to the "Building a Patch" stage and incorporate this fix into the multicast-base edits we make there:

~~~
git add content/browser/multicast/multicast_receiver_manager.cc
git commit -m "include directly used header file (fix build error from header changes)"
git checkout multicast-base
# manual change, or git cherry-pick -i experimental-fixing-branch
# then git add and git commit again.
~~~

### Other failures

There's a number of other failures that can happen, like maybe the network connectivity breaks while fetching the code or doing one of the curls for version discovery, or you run out of disk space.

In general, the best approach is to check your disk space and clean up if necessary.  But always remove the container with `docker rm cbuild-${CHAN}`, then re-launch manually: `CHAN=${CHAN} ./nightly.sh`.  If you're logged in remotely, be sure to do this in a screen or tmux session or another method that will let you leave it running while you're disconnected, otherwise disconnecting will kill it (and it takes an unreasonably long time to run).

## Building a Patch

When there's a failure that needs a new patch built (usually a build failure or a patch application failure), you'll need to do a little bit of updating some branches and tags so the automated nightly build process can continue checking that we're up to date moving forward.

### Figuring Out the Versions

Whether an apply failed or the build failed, you'll need to know what's the patch you're working with and what's the version you're trying to build on top of.

From the host, these are in nightly-junk/bld-${CHAN}/src/out/Default/env.sh`.

The place to work is in the src directory usually:

~~~
cd nightly-junk/bld-dev/src
# or cd nightly-junk/bld-stable/src
~~~

Then load the values:

~~~
. out/Default/env.sh
~~~

This should set VERSION, LASTGOOD, CHAN, and BP, which you can use to copy/paste most of the commands.

### Moving to a Newer Merge Base

If VERSION is on a different release branch than LASTGOOD, you'll need to use a newer merge base.

(The merge base is the commit in main where the branch forks off.)

Sometimes you can skip this step, for instance when the old build was for 91.0.4449.4, and you get a new compile error when trying 91.0.4449.6.

~~~
$ ( [ "$(git merge-base ${LASTGOOD} main)" = "$(git merge-base ${VERSION} main)" ] && echo "ok to leave alone" ) || echo "needs to move merge base"
needs to move merge base
~~~

This generally is associated with a change in the first 3 numbers of the version (though this is not enforced by git and should probably not be strictly relied upon, it's just a chromium branch design choice that could theoretically change, and I don't know how strictly enforced it is):

~~~
$ ( [ "$(echo ${VERSION} | cut -f -3 -d.)" != "$(echo ${LASTGOOD} | cut -f -3 -d.)" ] && echo "different version branch" ) || echo "same version branch"
different version branch
~~~

For dev, (where this changes frequently) we'll move the multicast/multicast-base branch to the merge-base of the latest dev release branch.  It's expected that if LASTGOOD's merge-base is different than VERSION's, so is multicast/multicast-base

~~~
$ ( [ "$(git merge-base multicast/multicast-base main)" = "$(git merge-base ${VERSION} main)" ] && echo "ok to leave alone" ) || echo "needs version base move"
needs version base move
~~~

For stable we instead work with a branch named "multicast-patch-X.Y.Z", where X, Y, and Z are the first 3 numbers from the chromium release branch, and when the new release of stable changes those first 3 numbers, we make a new branch.

If it needs moving and has a different version branch, the commands you'll use for this stage look like this:

~~~
NEWBASE=$(git merge-base ${VERSION} main)
git checkout --track multicast/multicast-base
cp out/Default/env.sh ..
# otherwise that can get annoyingly lost cleaning leftover junk:
git clean -ffdx
cp ../env.sh out/Default/env.sh
git merge ${NEWBASE}
# fix merge conflicts
git commit -m "Merged to branch point for ${BP} releases"
git tag -a -m "Branch point for adding multicast to ${BP} releases." mcbp-${BP}
~~~

For an update to stable, it's slightly different:

~~~
NEWBASE=$(git merge-base ${VERSION} main)
OLDBP=$(echo ${LASTGOOD} | cut -f -3 -d.)
git checkout ${NEWBASE}
git checkout -b multicast-patch-${BP}
git merge -m "Merge multicast from mcbp-${OLDBP} on top of new stable multicast branch for ${BP}"  mcbp-${OLDBP}
# fix merge conflicts
# git commit -m "Merge multicast from mcbp-${OLDBP} on top of new stable multicast branch for ${BP}"
git tag -a -m "Branch point for adding multicast to ${BP} releases." mcbp-${BP}
~~~

After that, you'll proceed to "Mapping onto a Release Tag".

#### Example

(NB: this example was from an earlier process that tried to use rebase instead of merge for multicast-base maintenance. But the fixes are similar, so I'll leave it for posterity.)

For example, here's what it looked like to rebase from 91.0.4449's branch to 91.0.4469's branch:

~~~
$ echo ${VERSION}
91.0.4469.4
$ NEWBASE=$(git merge-base ${VERSION} main)
$ echo ${NEWBASE}
8563c4cd2f6a2323d29efc31eced6a9ee1e39b10
$ git checkout --track multicast/multicast-base
Updating files: 100% (26261/26261), done.
Previous HEAD position was ba2934983bf5 Publish DEPS for 91.0.4469.4
Branch 'multicast-base' set up to track remote branch 'multicast-base' from 'multicast'.
Switched to a new branch 'multicast-base'
$ git rebase ${NEWBASE}
~~~

This had a merge conflict, which was why the patch apply had failed.  Running `git status` showed the problem file:

~~~
Unmerged paths:
  (use "git restore --staged <file>..." to unstage)
  (use "git add <file>..." to mark resolution)
	both modified:   content/browser/browser_interface_binders.cc
~~~

Opening that file in an editor and searching for '=====' showed that the conflict was the usual "another edit happened on the same line":

~~~
<<<<<<< HEAD
  map->Add<blink::mojom::Authenticator>(
      base::BindRepeating(&RenderFrameHostImpl::GetWebAuthenticationService,
=======
  map->Add<network::mojom::MulticastReceiverOpener>(
      base::BindRepeating(&RenderFrameHostImpl::CreateMulticastReceiverOpener,
>>>>>>> initial multicast API, base functionality
                          base::Unretained(host)));
~~~

We fix it so that both edits are present in the final product (most merge conflicts are this kind of trivial, but not all):

~~~
  map->Add<blink::mojom::Authenticator>(
      base::BindRepeating(&RenderFrameHostImpl::GetWebAuthenticationService,
                          base::Unretained(host)));

  map->Add<network::mojom::MulticastReceiverOpener>(
      base::BindRepeating(&RenderFrameHostImpl::CreateMulticastReceiverOpener,
                          base::Unretained(host)));
~~~

Then we git add the file and git rebase --continue:

~~~
$ git add content/browser/browser_interface_binders.cc
$ git rebase --continue
Applying: initial multicast API, base functionality
~~~

We tag the point at which we branched from main with fixed merge conflicts, so we can access it later.  (This is needed in order to reproduce builds for versions from this release branch at the upstream, since we needed to make edits to resolve a merge conflict.)

~~~
$ BP=$(echo ${VERSION} | cut -f -3 -d.)
$ echo ${BP}
91.0.4469
$ git tag -a -m "Branch point for adding multicast to ${BP} releases." mcbp-${BP}
~~~

### Mapping Onto a Release Tag

After the above step (or if the above step was not necessary because the new version is in the same branch as the prior version) the `git merge-base main` for the multicast-base branch and the target VERSION tag.

~~~
$ ( [ "$(git merge-base multicast-base main)" = "$(git merge-base ${VERSION} main)" ] && echo "multicast-base ok to leave alone" ) || echo "multicast-base still needs moving to 'git merge-base ${VERSION} main'"
multicast-base ok to leave alone
~~~

This means the multicast-base branch is pointing at a particular commit from the upstream main branch, with the multicast API changes on top of it.  However, the commit from the main branch is never the same as the release commit.  (At the very least, the DEPS and chrome/VERSION files will be different.)

At this point we make a branch off multicast-base, which is at a sort of "point in main+multicast" state, and rebase it to the release tag, which has extra changes since it was forked from main. If you are not already on the multicas-base branch, make sure to `git checkout multicast-base` (or `git checkout --track multicast/multicast-base`, if you didn't do it during the prior step), then make a local branch to rebase to the release tag inside it (the multicast-base branch SHOULD NOT be used for that rebase):

~~~
$ git branch
  main
* multicast-base
$ git checkout -b temp-patch-branch
Switched to a new branch 'temp-patch-branch'
$ git merge -m "Merge ${VERSION} on top of mcbp-${BP}" ${VERSION}
~~~

If that results in a merge conflict, usually it's best to make the fix in multicast-base branch (by doing a `git stash`, then a `git checkout multicast-base`, followed by edits and `git add` of the files that need fixing, and `git commit -m "fixed merge problems"`), and then do another git checkout -b to a new temporary branch.

However, sometimes it might be better to instead produce a multicast-patch-\<version\> branch instead, when the change should not go into multicast-base for some reason.

The basic heuristic here is to try putting the fix in multicast-base, but if that produces a failure like a merge conflict while rebasing to ${VERSION}, or a build failure whose fix causes a merge conflict when rebasing, roll back the change and make a patch branch instead with `git checkout -b` (or git switch -c).  There might be other times a patch branch is justified, but that's expected to cover the most common cases.

The important thing to remember is that multicast-base is just the multicast-related changes on top of a commit from the main branch.  Anything version-specific should be forked off to a version-specific branch, to the extent it can be determined.  But it can be a fuzzy line.

When there is a patch branch for an earlier release on this release branch, you generally should fork from that patch branch instead of from multicast-base, since that's what it's there for.

So whichever branch you're forking from, you checkout to that branch and then `git checkout -b dummy-patch` (you can use whatever name you like, this branch doesn't get pushed to the repo, though the commit we use it to generate will be tagged and pushed).

Most of the time this looks like:

~~~
git checkout multicast-base
git checkout -b dummy-patch
git merge ${VERSION}
~~~

It's useful here to try building (and ideally tests), by entering the docker container and running the build:

~~~
docker start -i cbuild-${CHAN}
autoninja -c out/Default chrome
~~~

If that works, we tag it:

~~~
git tag -a -m "Multicast API patched onto ${VERSION}" mc-${VERSION}
~~~

### Testing With Local Patch File

The diff between the new tag and the release tag is the patch that we want to use as the patch for nightly.sh, so we dump that to a local file (FD for FORKDIR):

~~~
$ FD=${HOME}/src/chromium_fork
$ git diff ${VERSION}..mc-${VERSION} > ${FD}/patches/from-${VERSION}-patch.diff
~~~

At this point we want to run the nightly build manually and ensure that it passes with this diff file against this target.

Running another `nightly.sh` build will unlink `nightly-junk/bld-${CHAN}` from its current location, which will make your prospective changes to the branch and tags harder to find.  So it's helpful here to move the temp directory with your prospective changes to a more easily visible location:

~~~
$ mv $(readlink nightly-junk/bld-${CHAN}) /tmp/bld-CURTEST
~~~

(NB: if you move this into your chromium_fork directory, it will make an unreasonably large context during the docker build that happens inside nightly.sh, so it's best to keep it elsewhere.)

To run the build, you remove the old container and explicitly set USE_PATCH and VER when calling nightly.sh.

Remember if you're logged in remotely to do it from a tmux or screen, or something that won't stop the build if your connection gets killed (with the command below, you can access it later if you lose connection with `screen -ls` and `screen -x`):

~~~
docker container rm cbuild-${CHAN}
rm -f screen.${CHAN}.log
screen -d -L -Logfile screen.${CHAN}.log -m /bin/bash -c "CHAN=${CHAN} USE_PATCH=patches/from-${VERSION}-patch.diff VER=${VERSION} ./nightly.sh"
~~~

If you want to watch it to make sure, you can:

~~~
tail -f screen.${CHAN}.log
~~~

If that completes successfully, it'll end up with a new .deb file in `nightly-junk/chromium-browser-mc-unstable_${VERSION}-1_amd64.deb`.  It'll take something like 8 hours or so, probably.

You're encouraged to test that the .deb behaves as it should before pushing the updates with new references.  TBD: explain how  and make better tests (probably not quite enough to just link to [multicast-ingest-platform](https://github.com/GrumpyOldTroll/multicast-ingest-platform) and a [demo page](https://htmlpreview.github.io/?https://github.com/GrumpyOldTroll/wicg-multicast-receiver-api/blob/master/demo-multicast-receive-api.html) for manual testing...)

### Fixing and Repeating

Sometimes the local patch file fails.  When this happens, you'll want to make the appropriate changes and retry.

This is almost like going back to the start of "Building a Patch" with a new failure, but because you've made tags at this point you'll have to remove them, and you'll want to put the changes you need into the right location, which is likely not where you are in the bld-CURTEST directory being used to build the patch, and maybe you've logged out while the build was running and need to reset the variables:

At this point, very likely you're in the "build failure" scenario, so it's helpful to check the proposed changes inside the in-progress build environment.  You want to capture a good starting point to diff against in another temp branch that won't be checked in from inside the new build with the patch that doesn't build:

~~~
$ cd src/chromium_fork
$ cd nightly-build/bld-dev/src
$ git checkout -b experimental-2
$ git add -A .
$ git commit -m "re-trying fix for build errors"
~~~

Then you can re-check the build before editing:

~~~
$ docker start -i cbuild-dev
$ cd /bld/src
$ autoninja -C out/Default chrome
~~~

Make the fixes you'll need, these 2 locations are hopefully pointing at the same location via a bind-mount.

You'll need to delete the prior tags, apply the patch, and make the new tags:

~~~
$ cd /tmp/bld-CURTEST/src
$ . out/Default/env.sh
$ BP=$(echo ${VERSION} | cut -f -3 -d.)
$ git tag --delete mcbp-${BP}
$ git tag --delete mc-${VERSION}
~~~

(Then either "git diff > patch.txt" in chromium_fork/nightly-junk/bld-dev/src and "git apply" that file to your multicast-base in /tmp/bld-CURTEST/src, or otherwise apply the changes as you like.)

Then in the staging area, generate another patch and retry the nightly.sh run:

~~~
$ cd /tmp/bld-CURTEST/src
$ . out/Default/env.sh
$ BP=$(echo ${VERSION} | cut -f -3 -d.)
$ git checkout multicast-base
$ git apply patch.txt
$ git commit -m "extra fixes after rebase to ${VERSION}"
$ git tag -a -m "Branch point for adding multicast to ${BP} releases." mcbp-${BP}
$ git checkout -b patch-try3
$ git rebase ${VERSION}
$ git tag -a -m "Multicast API patched onto ${VERSION}" mc-${VERSION}
$ FD=${HOME}/src/chromium_fork
$ git diff ${VERSION}..mc-${VERSION} > ${FD}/patches/from-${VERSION}-patch.diff
$ docker container rm cbuild-${CHAN}
$ screen -d -L -Logfile screen.${CHAN}.log -m /bin/bash -c "CHAN=${CHAN} USE_PATCH=patches/from-${VERSION}-patch.diff VER=${VERSION} ./nightly.sh"
~~~

## Pushing the Updated Patch

Now there's some new tags and commits added to the local clone of the repo, so these need to be pushed to the multicast fork online repo.

If you've done the "Testing With Local Patch File" steps, you'll hopefully have your changes sitting in something like `/tmp/bld-CURTEST/src`, otherwise maybe your changes will be inside `nightly-junk/bld-${CHAN}/src`, or possibly one of the /tmp/chromium-build-xxxx directories if you didn't move it earlier.

Regardless, the point of this part is to get the changes that were needed checked in to the forked chromium branch, so that future builds can use them to produce the patch as a diff between 2 checked-in tags.

If you haven't updated upstream-main, that should be straightforward.  This should hopefully never have merge conflicts, because upstream-main in the fork is exactly tracking the origin main.

For pushing, it can be helpful (but not required) to set the origin to use ssh instead of the https it used during the build process to fetch:

~~~
git remote set-url multicast git@github.com:GrumpyOldTroll/chromium.git
~~~

Updating upstream-main should always be trivial:

~~~
git checkout --track multicast/upstream-main
git rebase main
git push multicast upstream-main
~~~

If you created any tags (generally mc-${VERSION} and/or mcbp-${BP}), push them.

If this is more like a working directory with a lot of junk tags, please be more targeted and push only the ones you changed.

You can check what tags you'd be pushing (this will likely include several new tags from the upstream, which it's fine to include, but should not include temporary stuff):

~~~
git push --dry-run multicast --tags
~~~

If that's just the expected new ones, you can `git push --tags multicast`.  Otherwise, please be a little more targeted to reduce clutter:

~~~
git push multicast mc-${VERSION}
git push multicast mcbp-${BP}
~~~

If you created any patch branches that should persist or moved multicast-base, push those:

~~~
git push multicast multicast-base
git push multicast multicast-patch-${BP}
~~~

### Updating the Patch Spec

The automated nightly build should generate the patch diff from commits checked into the appropriate repositories, rather than carrying around a checked-in patch file.  This hopefully will ensure that the build artifacts are checked in and pushed whenever the nightly build is succeeding.

If you had to do a manual fix, the build state is currently broken, and you can put it back into a self-sustaining mode by giving the build server a LAST_GOOD.${CHAN}.sh file that will make it rebuild:

~~~
FD=${HOME}/src/chromium_fork
cd ${FD}
cat > LAST_GOOD.${CHAN}.sh <<EOF
LAST_GOOD_DIFF_SPEC="${VERSION}..mc-${VERSION}"
LAST_GOOD_DIFF_SHA256=
LAST_GOOD_BRANCH=
LAST_GOOD_TAG=${VERSION}
EOF
~~~

It's not especially recommended, but if you want to prevent rebuilding what you just checked in (and instead wait until there's a new version to try before attempting a fully automated build), you can provide the expected values for the BRANCH and SHA256 settings.  Ideally you will also include a new URL in the CURRENT_BINARIES.${CHAN}.md and upload the .deb you built to its link:

~~~
cat > LAST_GOOD.${CHAN}.sh <<EOF
LAST_GOOD_TAG=${VERSION}
LAST_GOOD_DIFF_SPEC="${VERSION}..mc-${VERSION}"
LAST_GOOD_DIFF_SHA256=$(shasum -a 256 patches/from-${VERSION}-patch.diff)
LAST_GOOD_BRANCH=$(git rev-list -n1 ${VERSION})
EOF
~~~

The cbuild-${CHAN} docker container doesn't get cleaned up if the nightly.sh script doesn't complete.  But more importantly, the temp directory for the build also doesn't get cleaned up, and that will be using a lot of space.

~~~
docker container rm cbuild-${CHAN}
rm -rf nightly-junk/bld-${CHAN}/*
rmdir $(readlink nightly-junk/bld-${CHAN})
~~~

You might also check whether there's leftover junk from other earlier runs.  You can check where the temp directory location is:

~~~
$ readlink nightly-junk/bld-${CHAN}
/tmp/chrome-build-EriUdn
~~~

If there's no builds active and you're trying to clean up, you can just delete all the matching ones.  These can be very large, so it's worth cleaning if there was an interruption to avoid disk full problems later, and these are easy to leave behind by accident, so if they're at all old, they should likely be thrown away:

~~~
$ ls -d /tmp/chrome-build-* | cat
/tmp/chrome-build-baNhJX
/tmp/chrome-build-EriUdn
/tmp/chrome-build-kBP1HI
/tmp/chrome-build-PjvkpZ
/tmp/chrome-build-tBEWwl
/tmp/chrome-build-y8RomO
$ rm -rf /tmp/chrome-build-*
~~~

After that, the next time the nightly build automatically runs here, it should be using the updated patch for this channel.

If you did this on a different location than the build server, be sure to push your changes to LAST_GOOD in this repo, so that the build server picks up the new diff info for the next run:

~~~
cd ../chromium_fork
git add LAST_GOOD.${CHAN}.sh
git commit -m "manual fix-up to build against ${VERSION}"
git push
~~~

It's not ideal, but checking in a LAST_GOOD.x.sh from a manual fix (without the BRANCH and SHA256 values) is preferable to letting the build server remain out of date for longer.

# Doing Actual Work

To do significant dev work on the multicast API, you'll want to take a recent multicast-base commit and branch from there, make your adjustment work well, rebase your feature branch to a new fetch of multicast-base, merge the changes back into multicast-base, and verify that it works when patched on top of a recent dev build.

The way to put the changes into LAST_GOOD.dev.sh are the same as what you do under Manual Changes to Fix Issues.

TBD: is there a saner way?

