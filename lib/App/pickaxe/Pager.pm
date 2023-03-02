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

sub statusbar ($self) {
    my $base  = $self->api->base_url->clone->query( key => undef );
    my $page =  $self->api->page( $self->pages->current->title, $self->version );
    my $title = $page->title;
    my $version = $page->version;
    my $author = $page->author->{name};
    my $percent;
    if ( $self->nlines == 0 ) {
        $percent = '100';
    }
    else {
        $percent = int( $self->current_line / $self->nlines * 100 );
    }
    return "pickaxe: $base $title rev $version by $author", sprintf( "--%3d%%", $percent );
}

sub render ($self) {
    if ( ($self->old_page || 0) != $self->pages->current ) {
        $self->version($self->pages->current->version);
        my $page = $self->pages->current;
        $self->old_page($page);
        $self->set_text( $page->rendered_text );
    }
    $self->next::method;
}

sub run ($self) {
    $self->next::method( $self->config->{keybindings} );
}

sub first_version ( $self, $key ) {
    my $page = $self->pages->current;
    $self->version( 1 );
    $self->set_text( $self->api->page( $page->title, $self->version)->rendered_text );
}

sub latest_version ( $self, $key ) {
    my $page = $self->pages->current;
    $self->version( $page->version );
    $self->set_text( $self->api->page( $page->title, $self->version)->rendered_text );
}

sub prev_version ( $self, $key ) {
    my $page = $self->pages->current;
    if ( $self->version > 1 ) {
        $self->version( $self->version - 1 );
        $self->set_text( $self->api->page( $page->title, $self->version)->rendered_text );
    }
}

sub next_version ( $self, $key ) {
    my $page = $self->pages->current;
    if ( $self->version < $page->version ) {
        $self->version( $self->version + 1 );
        $self->set_text( $self->api->page( $page->title, $self->version)->rendered_text );
    }
}

1;
