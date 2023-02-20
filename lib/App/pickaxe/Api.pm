package App::pickaxe::Api;
use Mojo::Base -signatures, -base;
use Mojo::UserAgent;

has base_url => sub {
    die "App::pickaxe::Api->base_url undefined.";
};

has ua => sub { Mojo::UserAgent->new };
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
    for my $page ( @{ $res->json->{wiki_pages} } ) {
        my $page = App::pickaxe::Page->new($page)->api($self);
        my $title = $page->title;
        $self->cache->{ $title }->[ $page->version ] = $page
    }
    return [map { $_->[-1] } values $self->cache->%*];
}

sub page ( $self, $title, $version = undef ) {
    if ( !$version || !$self->cache->{ $title }->[ $version] ) {
        my $url = $version ? "wiki/$title/$version.json" : "wiki/$title.json";
        my $res = $self->get($url);
        if ( $res->is_success ) {
            my $page = $res->json->{wiki_page};
            $page->{text} =~ s/\r//g;
            $self->cache->{ $title }->[ $page->{version} ] =
                App::pickaxe::Page->new( $page )->api($self);
        }
    }
    return $self->cache->{ $title }->[ $version || -1];
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
    my $res   = $self->get(
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
        $page->{text} = delete $page->{description};
        $page = { %$page, %{ $pages{ $page->{title} } } };
        $page->{text} =~ s/\r\n/\n/gs;
        delete $page->{datetime};
        $page = App::pickaxe::Page->new($page)->api($self);
    }
    return \@matching_pages;
}

package App::pickaxe::Page;
use Mojo::Base -base, -signatures;
use Text::Wrap 'wrap';
use Mojo::Util 'html_unescape', 'tablify';

has 'title';
has 'version';
has 'created_on';
has 'updated_on';

has 'api', undef, weak => 1;

sub fetch_all ( $self ) {
    my $version = $self->version;
    my $title   = $self->title;
    my $res     = $self->api->get("wiki/$title/$version.json");
    if ( $res->is_success ) {
        my $page = $res->json->{wiki_page};
        $page->{text} =~ s/\r\n/\n/gs;
        for my $key ( keys %$page ) {
            $self->$key( $page->{$key} );
        }
    }
    return;
}

has parent => sub ($self) {
    $self->fetch_all;
    return $self->parent;
};

has comments => sub ($self) {
    $self->fetch_all;
    return $self->comments;
};

has author => sub ($self) {
    $self->fetch_all;
    return $self->author;
};

has text => sub ($self) {
    $self->fetch_all;
    return $self->text;
};

has url => sub ($self) {
    my $url = $self->api->base_url->clone->path( "wiki/" . $self->title );
    $url->query( key => undef );
    return $url->to_string;
};

has rendered_text => sub ( $self ) {

    my $text = $self->text;

    ## Move <pre> to it's own line
    $text =~ s/^(\S+)(<\/?pre>)/$1\n$2/gms;
    $text =~ s/(<\/?pre>)(\S+)$/$1\n$2/gms;

    ## Remove empty lists
    $text =~ s/^\s*[\*\#]\s*\n//gmsx;

    ## Unscape html entities
    $text = html_unescape($text);

    # Remove header ids
    $text =~ s/^h(\d)\(.*?\)\./h$1./gms;

    ## Collapse empty lines;
    $text =~ s/\n{3,}/\n\n\n/gs;
    $text =~ s/\r\n/\n/g;

    my @table;
    my $pre_mode = 0;
    my @lines;
    use Data::Dumper;
    # if ($self->version == 235 ) { die Dumper [ split("\n",  $text ) ] };
    for my $line ( split( "\n", $text ) ) {
        if ( $line =~ /<pre>/ ) {
            $pre_mode = 1;
        }
        elsif ( $line =~ /<\/pre>/ ) {
            $pre_mode = 0;
        }
        elsif ($pre_mode) {
            push @lines, "    " . $line;
        }
        elsif ( $line =~ /^\s*\|(.*)\|\s*$/ ) {
            push @table,
              [ map { s/_\.//; s/^\s*//; s/\s*$//; $_ } split( '\|', $1 ) ];
        }
        elsif (@table) {
            push @lines, split( "\n", tablify( \@table ) );
            undef @table;
            redo;
        }
        elsif ( $line =~ /^(\s*[\*\#]\s*)\S/ ) {
            push @lines, split( "\n", wrap( '', ' ' x length($1), $line ) );
        }
        elsif ( $line eq '' ) {
            push @lines, $line;
        }
        else {
            $line =~ /^(\s*)/;
            push @lines, split( "\n", wrap( $1, $1, $line ) );
        }
    }
    if (@table) {
        push @lines, split( "\n", tablify( \@table ) );
    }
    return join("\n",@lines);

};

1;
