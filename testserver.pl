#!/usr/bin/perl

use Mojolicious::Lite -signatures;
use Mojo::File 'path';
use Mojo::Util 'decode';
use Mojo::Date;

my $dir = $ENV{REDMINE_BASE_DIR};

my %pages;

my @files = path($dir)->list->grep(qr/\.txt$/)->each;

for my $file ( @files ) {
    my $basename = decode( 'utf-8', $file->basename('.txt'));
    my $mtime = Mojo::Date->new($file->stat->mtime)->to_datetime;
    my ($uid,$name) = (getpwuid($file->stat->uid))[2,6];

    $pages{ $basename } = {
        title => $basename,
        text  => decode('utf-8', $file->slurp),
        author => { id => $uid, name => $name },
        comments => '',
        created_on => $mtime,
        updated_on => $mtime,
        version => 0,
    };
}

get '/projects/foo/wiki/index', [ format => ['json']] => sub {
    my $c = shift;
    $c->render( json => { wiki_pages => [ values %pages ] } );
};

get '/projects/foo/wiki/:version/:title', [ format => ['json']] => sub {
    my $c = shift;
    my $page = $pages{ $c->stash('title') };
    if ($page ) {
        $c->render( json => { wiki_page => $page } );
    }
    else {
        $c->render( status => 404, text => '' );
    }
};

get '/projects/foo/wiki/:title', [ format => ['json']] => sub {
    my $c = shift;
    my $page = $pages{ $c->stash('title') };
    if ($page ) {
        $c->render( json => { wiki_page => $page } );
    }
    else {
        $c->render( status => 404, text => '' );
    }
};

put '/projects/foo/wiki/:title', [ format => ['json']]  => sub {
    my $c = shift;
    my $title = $c->stash('title');
    my $text = $c->req->json->{wiki_page}->{text};

    my $time = Mojo::Date->new->to_datetime;
    if ( my $page = $pages{ $title } ) {
        $page->{text} = $text,
        $page->{updated_on} = $time;
        use Data::Dumper;
        warn Dumper $page;

        $c->render( status => 204, text => '' );
    }
    else {
        my ($uid,$name) = (getpwuid($<))[2,6];
        $pages{ $title } = {
            title => $title,
            text  => $text,
            author => { id => $uid, name => $name },
            comments => '',
            created_on => $time,
            updated_on => $time,
            version => 0,
        };
        $c->render( status => 201, text => '' );
    }
};

del '/projects/foo/wiki/#title', [ format => ['json' ]] => sub {
    my $c = shift;
    delete $pages{ $c->stash('title') };
    $c->render( status => 204, text => '' );
};

get '/projects/foo/search', [ format => ['json' ]] => sub {
    my $c = shift;
    my $q = $c->param('q');
    my @result = grep { $_->{text} =~ $q } values %pages;
    $c->render( json => { wiki_pages => \@result } );
};

app->start;
