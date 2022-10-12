package App::pickaxe::Api;
use Mojo::Base -signatures, -base;
use Mojo::UserAgent;

has ua => sub { Mojo::UserAgent->new };
has 'base_url';

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
    else {
        die( 'Error saving wiki page: ' . $res->message );
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
    if ( $res->is_success ) {
        return
          [ map { App::pickaxe::Api::Page->new($_)->api($self) } @{ $res->json->{wiki_pages} } ];
    }
    return [];
}

sub page ( $self, $title ) {
    my $res = $self->get("wiki/$title.json");
    if ( $res->is_success ) {
        return App::pickaxe::Api::Page->new($res->json->{wiki_page})->api($self);
    }
    return;
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

sub search ( $self, $query ) {
    my %pages = map { $_->{title} => $_ } @{ $self->pages };
    my $res = $self->get(
        "search.json",
        q          => $query,
        wiki_pages => 1,
        limit      => 100,
        offset     => 0
    );
    return if !$res->is_success;
    my $data           = $res->json;
    my @matching_pages = @{ $data->{results} };

    return if !@matching_pages;

    my $total_count = $data->{total_count};
    my $offset      = $data->{offset};
    while ( $total_count != @matching_pages ) {
        my $res = $self->get(
            "search.json",
            q          => $query,
            wiki_pages => 1,
            limit      => 100,
            offset     => $offset + 100,
        );
        return if !$res->is_success;
        my $data = $res->json;
        $offset = $data->{offset};
        push @matching_pages, @{ $data->{results} };
    }

    for my $page (@matching_pages) {
      $page->{title} =~ s/^Wiki: //;
      $page = { %$page, %{ $pages{ $page->{title} }}};
      $page->{text} = delete $page->{description};
      delete $page->{datetime};
      $page = App::pickaxe::Api::Page->new($page)->api($self);
    }
    return \@matching_pages;
}

package App::pickaxe::Api::Page;
use Mojo::Base -base, -signatures;

has 'title';
has 'version';
has 'created_on';
has 'updated_on';

has 'parent';
has 'author';
has 'comments';

has 'api', undef, weak => 1;

has 'text' => sub ($self ) {
    my $version = $self->version;
    my $title = $self->title;
    my $res = $self->api->get("wiki/$title/$version.json");
    if ( $res->is_success ) {
        my $text = $res->json->{wiki_page}->{text};
        $text =~ s/\r\n/\n/gs;
        return $text;
    }
    return '';
};

sub url ( $self ) {
    my $url = $self->api->base_url->clone->path("wiki/" . $self->title);
    $url->query( key => undef );
    return $url->to_string;
};

1;
