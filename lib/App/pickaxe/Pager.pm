package App::pickaxe::Pager;
use Mojo::Base -signatures, 'App::pickaxe::Base', 'App::pickaxe::UI::Pager';

has helpbar => "q:Quit e:Edit /:Find o:Open y:Yank D:Delete ?:Help";
has 'old_page';
has 'version';

sub next_item ( $self, $key ) {
    $self->pages->next;
}

sub prev_item ( $self, $key ) {
    $self->pages->prev;
}

sub diff_page ( $self, $key ) {
    my $version = $self->version;
    $self->next::method( $version - 1, $version );
}

sub next_heading ( $self, $key, $direction = 1 ) {
    my @lines = @{ $self->lines };
    my $pos   = $self->current_line;

    my @indexes =
      $direction == 1
      ? ( $pos + 1 .. @lines - 1 )
      : ( reverse( 0 .. $pos - 1 ) );

    for my $index (@indexes) {
        if ( $lines[$index] =~ /^h\d\./ ) {
            $self->goto_line($index);
            return;
        }
    }
    $self->message("No heading found.");
    return;
}

sub prev_heading ( $self, $key ) {
    $self->next_heading( $key, -1 );
}

sub statusbar ($self) {
    my $page = $self->api->page( $self->pages->current->title, $self->version );
    my $fmt  = App::pickaxe::Format->new(
        format     => $self->config->pager_status_format,
        identifier => {
            a => sub { $page->author->{name} },
            v => sub { $page->version },
            t => sub { $page->title },
            b => sub { $self->api->base_url->clone->query( key => undef ) },
            p => sub {
                if ( $self->nlines == 0 ) {
                    return '100';
                }
                return int( $self->current_line / $self->nlines * 100 );
            },
        }
    );
    return $fmt->printf($self);
}

sub render ($self) {
    if ( ( $self->old_page || 0 ) != $self->pages->current ) {
        $self->version( $self->pages->current->version );
        my $page = $self->pages->current;
        $self->old_page($page);
        $self->set_text( $page->rendered_text );
    }
    $self->next::method;
}

sub run ($self) {
    $self->next::method( $self->config->{keybindings} );
}

sub delete_page ( $self, $key ) {
    $self->next::method($key);
    if ( $self->pages->empty ) {
        $self->exit(1);
    }
}

sub first_version ( $self, $key ) {
    my $page = $self->pages->current;
    $self->version(1);
    $self->set_text(
        $self->api->page( $page->title, $self->version )->rendered_text );
}

sub latest_version ( $self, $key ) {
    my $page = $self->pages->current;
    $self->version( $page->version );
    $self->set_text(
        $self->api->page( $page->title, $self->version )->rendered_text );
}

sub prev_version ( $self, $key ) {
    my $page = $self->pages->current;
    if ( $self->version > 1 ) {
        $self->version( $self->version - 1 );
        $self->set_text(
            $self->api->page( $page->title, $self->version )->rendered_text );
    }
}

sub next_version ( $self, $key ) {
    my $page = $self->pages->current;
    if ( $self->version < $page->version ) {
        $self->version( $self->version + 1 );
        $self->set_text(
            $self->api->page( $page->title, $self->version )->rendered_text );
    }
}

1;
