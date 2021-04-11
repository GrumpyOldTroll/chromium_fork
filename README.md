# Overview

This repo is for maintaining a [fork of chromium](https://github.com/GrumpyOldTroll/chromium) that includes a [multicast API](/https://github.com/GrumpyOldTroll/wicg-multicast-receiver-api), and to regularly sync it from upstream.  The target is to stay up to date daily with the latest dev and stable builds, with a 1-week grace period when manual fixes are needed.

# Build Process

The automated nightly build tries applying the last known good patch on top of the current dev and stable release tags from the chromium upstream.

Whenever that fails, or whenever there's new edits to the multicast API feature, new commits get folded into the multicast API fork and the last good patch url gets updated so that future builds start hopefully working again.

# Branch and Tag Organization

## Branches:

 * [multicast-base](TBD) is where the baseline multicast implementation is to be developed.  This should remain a branch with a usable history about the multicast-API-related changes, uncorrupted by a lot of version and merge-related junk (though there will likely be several hopefully-minor ones where changes are needed to stay integrated with the upstream).  This branch starts from a specific commit off main, and it rebases to new main commits that are the [merge base](https://git-scm.com/docs/git-merge-base) commits for new release branches from the upstream.  Feature work should generally branch from here, do the dev work, rebase from this branch (in case it moved), and then merge the change into this branch, then make sure the last good url points to commits that incorporate these changes. (That may require making a tag based on a rebase of this branch up to the current last known good version before these changes were applied.)
   * This branch should specifically avoid pulling any of the version-specific changes to DEPS or chrome/VERSION in upstream release branches (to the point that we might break history to reverse this if it happens by accident, as it seems to make rebasing very painful). In general, this is done by being careful to rebase only to commits from upstream-main, not any version branches.
 * multicast-patch-\<version\> gets created for version branches when they have merge conflicts or build or runtime errors that need fixing on top of multicast-base in order to rebase to a release tag's commit.  Usually these fixes can be done in multicast-base instead, but sometimes they might need a branch.
 * [multicast-stable-tracking](TBD) is updated when the upstream stable release changes.  This is equivalent to "multicast-patches-\<version\>" for the version of the latest stable release (89.0.4389 at the time of this writing), but we carry it with an abstracted name, and even if there are no fixes needed because the stable release gets thousands of updates such that a rebase of a branch containing the multicast changes from the point where it branched from main to the release tag can take minutes to apply.  When the base version for the stable release branch changes upstream, this will get renamed in to multicast-patches-\<version\> and a new branch will be created for the new stable branch, and it will be named multicast-stable-tracking.  Since this is a history-breaking strategy, substantial work should not generally be done forking from this branch, this is intended generally just to cache the integration patchs specific to the stable release.
 * [upstream-main](TBD) exactly tracks the [upstream main](https://chromium.googlesource.com/chromium/src/+/refs/heads/main) branch, lagging behind by hopefully-less-than-a-week.  It should never contain anything different than the upstream main.  If it accidentally diverges for some reason, we'll break history on this branch to put it back in sync.

We don't keep a branch for tracking dev releases like we do for stable because the rebranching off main for a new dev release happens too often.  However, branching off multicast-base and rebasing to the latest dev tag from upstream is generally equivalent to what that branch would be, for the latest dev build.

## Tags

We use tags to help track the commit chains for builds we made that included the multicast API.

If we had a successful build, there should be 2 tags, one of which is shared across multiple updates for a major release branch.

 - mcbp-\<version-base\>, e.g. mcbp-89.0.4389.  This was the commit that resulted from rebasing multicast-base to the merge-base commit that's common to the version branch and main (as reported by git merge-base).  "bp" in the name stands for "branch point".
 - mc-\<version\>: e.g. mc-89.0.4389.82.  This commit results from rebasing a branch starting from the corresponding mcbp-\<version-base\> tag to the commit at the release version tag.

# Manual Changes to Fix Issues

The intent is to make this part as painless as possible since it represents the majority of instances of code changes, because merging dev work on the multicast feature code tends to be a much slower pace of individual edits at this stage.  Chromium gets a lot of commits, and some of them have merge failures with this (relatively large) feature.

(Suggestions that can improve on this process are very welcome, as it seems more complex than the ideal, but it MUST fit into a nightly automated build workflow that requires no manual intervention for the most common case of not having new conflicts.)

Usually the need for a new edit will come from a nightly build failure on dev.  This will send an a email to the select group of champions who are holding this fork together.

The easiest way to fix it involves getting onto the build server and getting into the nightly docker container, which will currently be in a broken build state.  (It is also generally possible to reproduce by pulling this repo and running ./nightly.sh locally, if you can't use the build server.)  A docker start -i should get you into the container:

~~~
CHAN=dev
docker start -i cbuild-${CHAN}
~~~

This should put you into the /bld/src directory, which should be mounted to a temp directory on the host that was created with [mktemp](https://www.gnu.org/software/autogen/mktemp.html) and currently has a symbolic link pointed to by nightly-junk/bld.

It's usually more convenient to go into nightly-junk/bld in the host to do the git commands to maintain the branches and end up making a new diff url, though it's possible to do it from inside the container if preferred.

You'll need to add the multicast remote and fetch tags and multicast-base:

~~~
cd nightly-junk/bld/src
git remote add multicast https://github.com/GrumpyOldTroll/chromium.git
git fetch multicast --all --tags
~~~

## Failure Modes

### Patch Application Failure

In the most common case, there's an error from the git apply (usually it's from some other line that got added to the same place one of the multicast hookups added a line).

In this case, the message from the end of the log file will say the git apply failed, and the git status will show a clean directory with no edits.

### Build Failure

Sometimes even though there's no merge failure, headers may have changed in a way that can cause build errors for a patch that applied cleanly.

In this case it'll usually be a compile error somewhere, and the git status will show a whole pile of multicast-related local file changes.

Like the Patch Application Failure case, this will generally require checking in a change, usually to multicast-base, and then rebasing to get back to this point.

However, in this case there might be an intermediate build that you can use to check your changes incrementally and quickly, before trying to troubleshoot the patch, and this can save time in fixing the issue.

If you want to make local edits before beginning the rebase process to do quick checks about what it takes to fix compiling, it's strongly encouraged to capture the snapshot you're making the changes against by making a local commit before doing anything:

~~~
git switch -c experimental-fixing-branch
git add -A .
git commit -m "capturing the applied last good diff before trying to fix build errors"
~~~

After that, go ahead and make edits and satisfy yourself they'll fix the build errors successfully:

~~~
autoninja -C out/Default chrome
~~~

Then proceed to Building a Patch.

### Other failures

There's a number of other failures that can happen, like maybe the network connectivity breaks while fetching the code or doing one of the curls for version discovery, or you run out of disk space.

In general, the best approach is to check your disk space and clean up if necessary.  But always remove the container with `docker rm cbuild-${CHAN}`, then re-launch manually: `CHAN=${CHAN} ./nightly.sh`.  If you're logged in remotely, be sure to do this in a screen or tmux session or another method that will let you leave it running while you're disconnected, otherwise disconnecting will kill it, and it takes an unreasonably long time to run.

## Building a Patch

When there's a failure that needs a new patch built (usually a build failure or a patch application failure), you'll need to do a little bit of updating some branches and tags so the automated nightly build process can continue checking that we're up to date.

### Moving to a Newer Merge Base

Sometimes you can skip this step, for instance when the old build was for 91.0.4449.4, and you get a new compile error when trying 91.0.4449.6.

However, when the dev build changes any of its first 3 numbers, like moving from 90.0.4430.X to 91.0.4449.Y, you'll need to do this step.

In general, we want the merge-base commit of multicast-base to be the same as the merge-base of the latest dev release branch.  If this is not the case, you should rebase multicast-base.

#### Example

For example, here's what it looked like at the time we were bringing the multicast-base forward from the stable release to one of the earlier dev releases we had a build for:

~~~
$ STABLE=89.0.4389.82
$ SBASE=$(git merge-base ${STABLE} main)
$ echo ${SBASE}
9251c5db2b6d5a59fe4eac7aafa5fed37c139bb7
$ git merge-base multicast-base main
9251c5db2b6d5a59fe4eac7aafa5fed37c139bb7
$ TARGET=90.0.4430.11
$ TBASE=$(git merge-base ${TARGET} main)
$ echo ${TBASE}
e5ce7dc4f7518237b3d9bb93cccca35d25216cbe
~~~

So we rebased it forward to the new target merge-base in main:

~~~
$ git checkout multicast-base
$ git rebase ${TBASE}
~~~

This had a few merge conflicts that had to be resolved.  git status said:

~~~
Unmerged paths:
  (use "git restore --staged <file>..." to unstage)
  (use "git add <file>..." to mark resolution)
	both modified:   third_party/blink/public/mojom/BUILD.gn
	both modified:   third_party/blink/renderer/modules/BUILD.gn
	both modified:   third_party/blink/renderer/modules/event_target_modules_names.json5
	both modified:   third_party/blink/renderer/modules/modules_idl_files.gni
~~~

These were all pretty trivial patches, generally multiple changes to apparently the same lines that messed up the diff.  For instance, the conflict in third_party/blink/public/mojom/BUILD.gn looked like this:

~~~
    "mime/mime_registry.mojom",
<<<<<<< HEAD
    "modal_close_watcher/modal_close_listener.mojom",
=======
    "multicast/multicast.mojom",
>>>>>>> initial multicast API, base functionality
    "native_io/native_io.mojom",
~~~

In this case you just fix it to have both lines and `git add` it.  Once those are all done, you `git rebase --continue`.  They were all similarly obvious, as they usually are.

After doing that, the merge-base of the multicast-base branch is at the target merge-base commit, and we've moved the branch forward to a newer release merge-base:

~~~
$ git merge-base multicast-base main
e5ce7dc4f7518237b3d9bb93cccca35d25216cbe
$ ( [ $(git merge-base multicast-base main) == ${TBASE} ] && echo yep ) || echo nope
yep
~~~

If we end up with a build for this, we'll also need this commit tagged as `mcbp-\<version-base\>` for later use.  It's probably best to just do it right now:

~~~
$ BPV=$(echo ${TARGET} | cut -f -3 -d.)
$ echo ${BPV}
90.0.4430
$ git tag -a -m "Branch point for adding multicast to ${BPV} releases." mcbp-${BPV}
~~~

### Mapping onto a Release Tag

Usually after the above step (or often before it) the multicast-base branch will share a merge-base commit in main with the target release.

At this point you'll usually make a branch off multicast-base and rebase it to the release tag.

If that rebase operation results in merge conflicts, usually it's best to update the `multicast-base` branch and try again.  Sometimes it might be better to instead produce a multicast-patch-\<version\> branch instead, when the change should not go into multicast-base for some reason.

The basic heuristic here is to try putting the fix in multicast-base, but if that produces a failure like a merge conflict while rebasing or a build failure whose fix causes a merge conflict when rebasing, roll back the change and make a patch branch instead with `git switch -c .  There might be other times a patch branch is justified, but that's expected to cover the most common cases.

When there is a patch branch for an earlier release on this release branch, you generally should fork from that patch branch instead of from multicast-base, since that's what it's there for.

So whichever branch you're forking from, you checkout to that branch and then `git checkout -b dummy-patch` (you can use whatever name you like, this branch doesn't get pushed to the repo, though the commit we use it to generate will).

Most of the time this looks like:

~~~
git checkout multicast-base
git checkout -b dummy-patch
git rebase ${TARGET}
~~~

At this point we have something we think should work if multicast-base was in a decent state, so we tag it:

~~~
git tag -a -m "Multicast API patched onto ${TARGET}" mc-${TARGET}
~~~

### Testing With Local Patch File

The diff between the new tag and the release tag is the patch that we want to use as the new LAST_GOOD_DIFF, so we dump that to a local file:

~~~
git diff ${TARGET}..mc-${TARGET} > ../chromium_fork/patches/from-${TARGET}-patch.diff
~~~

At this point we want to run the nightly build manually and ensure that it passes with this diff file against this target.  You can do that by explicitly setting USE_PATCH and VER when calling nightly.sh:

~~~
cd ../chromium_fork
USE_PATCH=patches/from-${TARGET}-patch.diff VER=${TARGET} ./nightly.sh
~~~

Remember if you're logged in remotely to do that from a tmux or screen, or something that lets you log out without stopping the build.

If that completes successfully, it'll end up with a new .deb file in `nightly-junk/chromium-browser-mc-unstable_${TARGET}-1_amd64.deb`.  It'll take something like 12 hours, probably.

You're encouraged to test that the .deb behaves as it should before pushing the updates with new references.  TBD: explain how

## Pushing the Updated Patch

Now there's some new tags and commits added to the local clone of the repo, so these need to be pushed to the multicast fork online repo:

~~~
TBD
~~~

After that, there's a URL that can be used instead of the local patch file we used for testing.  Verify that the sha256 is the same, then update the LAST_GOOD.${CHAN}.sh file to use that URL instead of the local patch file, and check it in.

~~~
TBD
# PATCHURL: if set it will curl this and git apply it.  You can get
#   these from github commits, e.g.:
#   https://github.com/GrumpyOldTroll/chromium/commit/da79e14e808debadfd1743222bcacd7dad41fdbe.patch

~~~

Now clean up the cbuild-${CHAN} docker container so that nightly build can auto-run again:

~~~
TBD
~~~

Now next time the nightly build automatically runs, it should be using the updated patch for this channel.

# Doing Actual Work

To do significant dev work on the multicast API, you'll want to take a recent multicast-base commit and branch from there, do work from the frozen location, and merge the work back into multicast-base once it's complete, and verify that it works with a dev build.

The way to put the changes into LAST_GOOD.dev.sh are the same as what you do under Manual Changes to Fix Issues.

TBD: is there a saner way?  Find it and change this workflow so we can maybe actually do some dev work here.

