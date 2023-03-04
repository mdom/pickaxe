#!/usr/bin/perl

use Mojolicious::Lite -signatures;
use Mojo::File 'path';
use Mojo::Util 'decode';
use Mojo::Date;
use Digest::SHA1 qw(sha1_hex);

my $dir = $ENV{MOJO_HOME};

my %pages;

my @files = path($dir)->list->grep(qr/\.txt$/)->each;
my %attachments;

for my $file (@files) {
    my $basename = decode( 'utf-8', $file->basename('.txt') );
    my $mtime    = Mojo::Date->new( $file->stat->mtime )->to_datetime;
    my ( $uid, $name ) = ( getpwuid( $file->stat->uid ) )[ 2, 6 ];

    push @{ $pages{$basename} },
      {
        title       => $basename,
        text        => decode( 'utf-8', $file->slurp ),
        author      => { id => $uid, name => $name },
        comments    => '',
        created_on  => $mtime,
        updated_on  => $mtime,
        version     => 1,
        attachments => [],
      };
}

get '/projects/foo/wiki/index', [ format => ['json'] ] => sub {
    my $c = shift;
    $c->render( json => { wiki_pages => [ map { $_->[-1] } values %pages ] } );
};

get '/projects/foo/wiki/:title/:version', [ format => ['json'] ] => sub {
    my $c    = shift;
    my $page = $pages{ $c->stash('title') };
    if ($page) {
        $c->render(
            json => { wiki_page => $page->[ $c->stash('version') - 1 ] } );
    }
    else {
        $c->render( status => 404, text => '' );
    }
};

get '/projects/foo/wiki/:title', [ format => ['json'] ] => sub {
    my $c    = shift;
    my $page = $pages{ $c->stash('title') };
    if ($page) {
        $c->render( json => { wiki_page => $page->[-1] } );
    }
    else {
        $c->render( status => 404, text => '' );
    }
};

put '/projects/foo/wiki/:title', [ format => ['json'] ] => sub {
    my $c           = shift;
    my $title       = $c->stash('title');
    my $text        = $c->req->json->{wiki_page}->{text};
    my $comments    = $c->req->json->{wiki_page}->{comments} || '';
    my $attachments = $c->req->json->{wiki_page}->{uploads}  || [];
    my ( $uid, $name ) = ( getpwuid($<) )[ 2, 6 ];
    my $author = { id => $uid, name => $name };

    my $time = Mojo::Date->new->to_datetime;
    if ( my $page = $pages{$title} ) {

        my $version = $c->req->json->{wiki_page}->{version};
        if ( defined $version && $version < @{ $pages{$title} } ) {
            $c->render( status => 409, text => '' );
            return;
        }

        my $new_page = { %{ $page->[-1] } };
        $new_page->{text}       = $text;
        $new_page->{updated_on} = $time;
        $new_page->{author}     = $author;
        $new_page->{comments}   = $comments;
        $new_page->{attachments} =
          [ @{ $new_page->{attachments} }, @$attachments ];

        $new_page->{version}++;

        push @{ $pages{$title} }, $new_page;

        $c->render( status => 204, text => '' );
    }
    else {
        push @{ $pages{$title} },
          {
            title       => $title,
            text        => $text,
            author      => $author,
            comments    => $comments,
            created_on  => $time,
            updated_on  => $time,
            version     => 1,
            attachments => $attachments,
          };
        $c->render( status => 201, text => '' );
    }
};

del '/projects/foo/wiki/#title', [ format => ['json'] ] => sub {
    my $c = shift;
    delete $pages{ $c->stash('title') };
    $c->render( status => 204, text => '' );
};

post '/uploads', [ format => ['json'] ] => sub ($c) {
    if ( $c->req->headers->content_type ne 'application/octet-stream' ) {
        return $c->render( status => '406', text => 'Not Acceptable' );
    }
    my $content = $c->req->body;
    my $token   = sha1_hex($content);
    $attachments{$token} = $content;
    $c->res->code(201);
    $c->render( json => { upload => { token => sha1_hex } } );
};

get '/projects/foo/search', [ format => ['json'] ] => sub {
    my $c      = shift;
    my $q      = $c->param('q');
    my $offset = $c->param('offset') || 0;
    my $limit  = $c->param('limit')  || 25;

    my @results = map {
        my $o = {%$_};
        $o->{title} = "Wiki: " . $o->{title};
        $o;
    } grep { $_->{text} =~ /\Q$q/ } map { $_->[-1] } values %pages;

    $c->render(
        json => {
            offset      => $offset,
            limit       => $limit,
            total_count => scalar @results,
            results     => [
                  @results <= $limit
                ? @results
                : @results[ $offset .. $offset + $limit - 1 ]
            ]
        }
    );
};

app->start;
