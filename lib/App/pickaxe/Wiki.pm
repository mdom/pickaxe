package App::pickaxe::Wiki;
use Mojo::Base -signatures, -base;

has 'api';
has selected => 0;
has prev_selected => 0;

sub current_page ($self) {
    $self->pages->[ $self->selected ];
}

has pages => sub {
    shift->get_pages;
};

sub refresh ($self) {
    $self->pages( $self->get_pages );
    $self->selected(0);
}

sub get_pages ($self) {
    my $res =
      eval { $self->api->get( "wiki/index.json" ) };
    if ($@) {
        die "Error connection server: " . $@ . "\n";
    }
    if ( !$res->is_success ) {
        die "Error connection server: " . $res->message . "\n";
    }
    $res->json->{wiki_pages};
}

sub select ( $self, $new ) {
    $self->prev_selected($self->selected);
    $self->selected($new);
    if ( $self->selected < 0 ) {
        $self->selected(0);
    }
    elsif ( $self->selected > @{ $self->pages } - 1 ) {
        $self->selected( @{ $self->pages } - 1 );
    }
}

sub search ($self, $query) {
        my $res     = $self->api->get("search.json", q => $query, wiki_pages => 1);
        my @results = @{ $res->json->{results} };

        return if !@results;

        my @found;

        my %pages = map { $_->{title} => $_ } @{ $self->all };

        for my $result (@results) {
            $result->{title} =~ s/^Wiki: //;
            push @found, $pages{ $result->{title} };
        }
        return \@found;
}

1;
