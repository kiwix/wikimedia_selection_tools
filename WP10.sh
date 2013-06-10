#!/usr/bin/env bash

WIKI=$1
CMD=$2

####################################
## CONFIGURATION

# Perl and sort(1) have locale issues, which can be avoided 
# by disabling locale handling entirely. 
LANG=C
export LANG

# Used by /bin/sort to store temporary files
TMPDIR=./$WIKI/target
export TMPDIR

##### END CONFIGURATION
####################################

usage() 
{
    echo "Usage: WP1.sh <wikiname> <command>"
    echo "  <wikiname> - such as enwiki, frwiki, ..."
    echo "  <command>  can be 'download', 'indexes', or 'counts'"
    exit
}

## Check command line arguments
if [ "$WIKI" = '' ]; then
  usage;
fi

case $CMD in
  indexes)   echo "Making indexes for $WIKI"  ;;
  download)  echo "Downloading files for $WIKI" ;;
  counts)    echo "Making overall counts for $WIKI"   ;;
  *)         usage                ;;
esac

####################################
if [ "$CMD" = "download" ]; then

# This used to download the dumps from download.wikimedia.org, but
# they're available on Tool Labs already so we just symlink them.

if [ ! -e "/public/datasets/public/$WIKI" ];
then
    echo "error: no dump are available for wiki '$WIKI'."
    exit
fi

mkdir -p ./$WIKI/source
mkdir -p ./$WIKI/target

LATEST=`ls -1 /public/datasets/public/$WIKI|sort|tail -n1` # Latest version

for file in pagelinks langlinks redirect categorylinks; do
	ln -fs /public/datasets/public/$WIKI/$LATEST/$WIKI-$LATEST-$file.sql.gz \
		./$WIKI/source/$WIKI-latest-$file.sql.gz
done

# End CMD = download

fi

####################################
if [ "$CMD" = "indexes" ]; then

function build_namespace_indexes() {
	namespace=$1;
	name=$2;
	
	echo ./$WIKI/target/${name}_pages_sort_by_ids.lst.gz
	if [ -e ./$WIKI/target/${name}_pages_sort_by_ids.lst.gz ]; then
		echo "...file already exists"
	else 
		# XXX BEWARE: This query was imputed based on what the old program seemed to be trying to do.
		# It may not be correct; we'll see what happens later on.
		echo "SELECT page_id, page_namespace, page_title, page_is_redirect FROM page WHERE page_namespace = $namespace ORDER BY page_id ASC;" \
		 | mysql -B --defaults-file=~/replica.my.cnf -h ${WIKI}.labsdb ${WIKI}_p \
		 | tr '\t' ' ' \ # MySQL outputs tab-separated; file needs to be space-separated.
		 | gzip > ./$WIKI/target/${name}_pages_sort_by_ids.lst.gz
	fi
}

## BUILD PAGES INDEXES
build_namespace_indexes 0 main

## BUILD TALK INDEXES
build_namespace_indexes 1 talk

# Categories may not be needed, so to save time they are disabled by default
## BUILD CATEGORIES INDEXES
build_namespace_indexes 14 categories

## BUILD PAGELINKS INDEXES - replaced by the next two files
#echo ./$WIKI/target/pagelinks.lst.gz
#if [ -e ./$WIKI/target/pagelinks.lst.gz ]; then 
#  echo "...file already exists"
#else
#  cat ./$WIKI/source/$WIKI-latest-pagelinks.sql.gz \
#   | gzip -d \
#   | tail -n +28 \
#   | ./bin/pagelinks_parser \
#   | gzip > ./$WIKI/target/pagelinks.lst.gz
#fi

## BUILD PAGELINKS COUNTS
  echo ./$WIKI/target/pagelinks_main_sort_by_ids.lst.gz
  if [ -e ./$WIKI/target/pagelinks_main_sort_by_ids.lst.gz ]; then 
    echo "...file already exists"
  else
    cat ./$WIKI/source/$WIKI-latest-pagelinks.sql.gz \
     | gzip -d \
     | tail -n +28 \
     | ./bin/pagelinks_parser2 \
     | sort -T$TMPDIR -n -t " " -k 1,1 \
     | gzip > ./$WIKI/target/pagelinks_main_sort_by_ids.lst.gz
  fi

  echo ./$WIKI/target/pagelinks.counts.lst.gz 
  if [ -e ./$WIKI/target/pagelinks.counts.lst.gz ]; then 
    echo "...file already exists"
  else
  time ( \
    ./bin/catpagelinks.pl ./$WIKI/target/main_pages_sort_by_ids.lst.gz \
                        ./$WIKI/target/pagelinks_main_sort_by_ids.lst.gz \
      | sort -T$TMPDIR -t " " \
      | uniq -c  \
      | perl -lane 'print $F[1] . " " . $F[0] if ( $F[0] > 1 );' \
      | sort -T$TMPDIR \
      | gzip > ./$WIKI/target/pagelinks.counts.lst.gz 
    )
  fi

## BUILD LANGLINKS INDEXES
  echo ./$WIKI/target/langlinks_sort_by_ids.lst.gz
  if [ -e ./$WIKI/target/langlinks_sort_by_ids.lst.gz ]; then 
    echo "...file already exists"
  else
    cat ./$WIKI/source/$WIKI-latest-langlinks.sql.gz \
     | gzip -d \
     | tail -n +28 \
     | ./bin/langlinks_parser \
     | sort -T$TMPDIR -n -t " " -k 1,1 \
     | gzip > ./$WIKI/target/langlinks_sort_by_ids.lst.gz
  fi

## BUILD REDIRECT INDEXES
  echo ./$WIKI/target/redirects_sort_by_ids.lst.gz
  if [ -e ./$WIKI/target/redirects_sort_by_ids.lst.gz ]; then 
    echo "...file already exists"
  else
    cat ./$WIKI/source/$WIKI-latest-redirect.sql.gz \
     | gzip -d \
     | tail -n +41 \
     | ./bin/redirects_parser \
     | sort -T$TMPDIR -n -t " " -k 1,1 \
     | gzip > ./$WIKI/target/redirects_sort_by_ids.lst.gz
  fi

  echo ./$WIKI/target/redirects_targets.lst.gz 
  if [ -e ./$WIKI/target/redirects_targets.lst.gz ]; then 
    echo "...file already exists"
  else
    perl bin/join_redirects.pl ./$WIKI/target/main_pages_sort_by_ids.lst.gz \
                               ./$WIKI/target/redirects_sort_by_ids.lst.gz \
                        ./$WIKI/target/pagelinks_main_sort_by_ids.lst.gz \
    | sort -T$TMPDIR \
    | gzip > ./$WIKI/target/redirects_targets.lst.gz
  fi

## Commented out because it's very large, but may not be needed
## BUILD CATEGORYLINKS INDEXES
#echo ./$WIKI/target/categorylinks_sort_by_ids.lst.gz
#if [ -e ./$WIKI/target/categorylinks_sort_by_ids.lst.gz ]; then 
#  echo "...file already exists"
#else
#cat ./$WIKI/source/$WIKI-latest-categorylinks.sql.gz  \
#  | gzip -d \
#  | tail -n +28 \
#  | ./bin/categorylinks_parser \
#  | sort -T$TMPDIR -n -t " " -k 1,1 \
#  | gzip > ./$WIKI/target/categorylinks_sort_by_ids.lst.gz
#fi

## BUILD LANGLINKS COUNTS
  echo ./$WIKI/target/langlinks.counts.lst.gz      
  if [ -e  ./$WIKI/target/langlinks.counts.lst.gz ]; then 
    echo "...file already exists"
  else
    ./bin/count_langlinks.pl  ./$WIKI/target/main_pages_sort_by_ids.lst.gz \
                              ./$WIKI/target/langlinks_sort_by_ids.lst.gz \
    | sort -T$TMPDIR -t " "\
    | gzip > ./$WIKI/target/langlinks.counts.lst.gz      
  fi

## BUILD LIST OF MAIN PAGES
  echo ./$WIKI/target/main_pages.lst.gz 
  if [ -e  ./$WIKI/target/main_pages.lst.gz ]; then 
    echo "...file already exists"
  else
    cat ./$WIKI/target/main_pages_sort_by_ids.lst.gz \
     | gzip -d \
     | perl -lane 'print $F[2]' \
     | sort -T$TMPDIR -t " " \
     | gzip > ./$WIKI/target/main_pages.lst.gz
  fi

# END if [ "$CMD" = "indexes" ];
fi  

####################################

## BUILD OVERALL COUNTS
if [ "$CMD" = "counts" ]; then 

  if [ ! -e ./$WIKI/source/hitcounts.raw.gz ]; then
   echo 
    echo "Error: You must obtain or create the file hitcounts.raw.gz"
   echo  "Place it in the directory ./$WIKI/source"
    exit
  fi

  echo ./$WIKI/target/counts.lst.gz
  if [ -e ./$WIKI/target/counts.lst.gz ]; then
    echo "...file already exists"
  else
    ./bin/merge_counts.pl ./$WIKI/target/main_pages.lst.gz \
                          ./$WIKI/target/langlinks.counts.lst.gz \
                          ./$WIKI/target/pagelinks.counts.lst.gz \
                          ./$WIKI/source/hitcounts.raw.gz \
     | ./bin/merge_redirects.pl ./$WIKI/target/redirects_targets.lst.gz \
     | sort -T$TMPDIR -t " "\
     | ./bin/merge_tally.pl \
     | gzip > ./$WIKI/target/counts.lst.gz
  fi
fi 
