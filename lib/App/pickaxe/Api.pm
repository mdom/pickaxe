package App::pickaxe::Api;
use Mojo::Base -signatures, -base;

use Mojo::UserAgent;
use App::pickaxe::Page;
use Mojo::File 'path';

has base_url => sub {
    die "App::pickaxe::Api->base_url undefined.";
};

has ua    => sub { Mojo::UserAgent->new };
has cache => sub { {} };

sub get ( $self, $path, %parameters ) {
    my $url = $self->base_url->clone->path($path);
    if (%parameters) {
        $url->query->merge(%parameters);
    }
    my $res = $self->ua->get( $url => { 'Content-Type' => 'application/json' } )
      ->result;
    if ( $res->code == 401 ) {
        die "Authentication failed.\n";
    }
    return $res;
}

sub save ( $self, $title, $text, $version = undef ) {
    my $url = $self->base_url->clone->path("wiki/$title.json");

    my $res = $self->ua->put(
        $url => json => {
            wiki_page =>
              { text => $text, ( $version ? ( version => $version ) : () ) }
        }
    )->result;

    if ( $res->is_success ) {
        return 1;
    }
    elsif ( $res->code == 409 ) {
        return 0;
    }
    die( 'Error saving wiki page: ' . $res->message );
}

sub attach_files ( $self, $title, @files ) {
    my $url = $self->base_url->clone->path("/uploads.json");
    my @tokens;
    for my $file (@files) {
        my $asset = Mojo::Asset::File->new( path => $file );
        my $post  = $self->ua->build_tx(
            POST => $url => { 'Content-Type' => 'application/octet-stream' } );
        $post->req->content->asset($asset);
        my $tx = $self->ua->start($post);
        push @tokens,
          {
            token    => $tx->res->json->{upload}->{token},
            filename => path($file)->basename
          };
    }
    while (1) {
        my $page = $self->page($title);
        my $res  = $self->ua->put(
            $url => json => {
                wiki_page => {
                    text    => $page->text,
                    version => $page->version,
                    uploads => \@tokens
                }
            }
        )->result;

        if ( $res->is_success ) {
            return 1;
        }
        elsif ( $res->code == 422 ) {
            return 0;
        }
        elsif ( $res->code == 409 ) {
            next;
        }
        die "Unknown response code from server: " . $res->code . "\n";
    }
}

sub delete ( $self, $title ) {
    my $url = $self->base_url->clone->path("wiki/$title.json");
    my $res = $self->ua->delete($url)->result;
    if ( !$res->is_success ) {
        return $res->message;
    }
    return;
}

sub pages ($self) {
    my $res = $self->get("wiki/index.json");
    for my $page ( @{ $res->json->{wiki_pages} } ) {
        my $page  = App::pickaxe::Page->new($page)->api($self);
        my $title = $page->title;
        $self->cache->{$title}->[ $page->version ] = $page;
    }
    return [ map { $_->[-1] } values $self->cache->%* ];
}

sub page ( $self, $title, $version = undef ) {
    if ( !$version || !$self->cache->{$title}->[$version] ) {
        my $url = $version ? "wiki/$title/$version.json" : "wiki/$title.json";
        my $res = $self->get($url);
        if ( $res->is_success ) {
            my $page = $res->json->{wiki_page};
            $page->{text} =~ s/\r//g;
            $self->cache->{$title}->[ $page->{version} ] =
              App::pickaxe::Page->new($page)->api($self);
        }
    }
    return $self->cache->{$title}->[ $version || -1 ];
}

sub projects ($self) {
    my $res = $self->get(
        "/projects.json",
        include => 'enabled_modules',
        limit   => 100,
        offset  => 0
    );
    return if !$res->is_success;
    my $data     = $res->json;
    my @projects = @{ $data->{projects} };

    return if !@projects;

    my $total_count = $data->{total_count};
    my $offset      = $data->{offset};

    while ( $total_count != @projects ) {
        my $res = $self->get(
            "/projects.json",
            include => 'enabled_modules',
            limit   => 100,
            offset  => $offset + 100,
        );
        return if !$res->is_success;
        my $data = $res->json;
        $offset = $data->{offset};
        push @projects, @{ $data->{projects} };
    }

    my @result;
  PROJECT:
    for my $project (@projects) {
        for my $module ( @{ $project->{enabled_modules} } ) {
            if ( $module->{name} eq 'wiki' ) {
                push @result, $project->{identifier};
                next PROJECT;
            }
        }
    }

    return \@result;
}

sub _search ( $self, $query, $offset = 0 ) {
    my $res = $self->get(
        "search.json",
        q          => $query,
        wiki_pages => 1,
        limit      => 100,
        offset     => 0
    );
    return if !$res->is_success;
    return $res->json;
}

sub search ( $self, $query ) {
    my $data = $self->_search($query);
    return if !$data;
    my @results = @{ $data->{results} };

    return if !@results;

    my $total_count = $data->{total_count};
    my $offset      = $data->{offset};
    while ( $total_count != @results ) {
        my $data = $self->_search( $query, $offset + 100 );
        last if !$data;
        $offset = $data->{offset};
        push @results, @{ $data->{results} };
    }
    return [
        map { $self->page( $_, -1 ) }
        map { $_->{title} =~ /^Wiki: (.*)/ } @results
    ];
}

1;
