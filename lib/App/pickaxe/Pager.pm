package App::pickaxe::Pager;
use Mojo::Base -signatures, 'App::pickaxe::Base', 'App::pickaxe::UI::Pager';

has helpbar => "q:Quit e:Edit /:Find o:Open y:Yank D:Delete ?:Help";
has 'old_page';

sub statusbar ($self) {
    my $base  = $self->api->base_url->clone->query( key => undef );
    my $title = $self->pages->current->title;
    my $percent;
    if ( $self->nlines == 0 ) {
        $percent = '100';
    }
    else {
        $percent = int( $self->current_line / $self->nlines * 100 );
    }
    return "pickaxe: $base $title", sprintf( "--%3d%%", $percent );
}

sub render ($self) {
    if ( $self->old_page ne $self->pages->current ) {
        my $page = $self->pages->current;
        $self->old_page($page);
        $self->set_text( $page->rendered_text );
    }
    $self->next::method;
}

sub run ($self) {
    my $page = $self->pages->current;
    $self->old_page($page);
    $self->set_text( $page->rendered_text );
    $self->next::method( $self->config->{keybindings} );
}

1;
