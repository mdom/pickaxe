package App::pickaxe::Pager;
use Mojo::Base -signatures, 'App::pickaxe::GUI::Pager';

my @delegate =
  qw(api open_in_browser add_page edit_page display_help delete_page add_attachment update_pages set_order set_reverse_order view_page search switch_project);

{
    no strict 'refs';
    for my $method (@delegate) {
        *{$method} = sub { shift->index->$method(@_) };
    }
}

has helpbar => "q:Quit e:Edit /:find o:Open %:Preview D:Delete ?:help";

has 'config';
has 'index';

sub statusbar ($self) {
    my $base  = $self->api->base_url->clone->query( key => undef );
    my $title = $self->index->current_page->title;
    my $percent;
    if ( $self->nlines == 0 ) {
        $percent = '100';
    }
    else {
        $percent = int( $self->current_line / $self->nlines * 100 );
    }
    return "pickaxe: $base $title", sprintf( "--%3d%%", $percent );
}

sub next_item ( $self, $key ) {
    $self->index->next_item($key);
}

sub prev_item ( $self, $key ) {
    $self->index->prev_item($key);
}

has 'old_page';

sub render ($self) {
    if ( $self->old_page ne $self->index->current_page ) {
        my $page = $self->index->current_page;
        $self->old_page($page);
        $self->set_lines( $page->rendered_text );
    }
    $self->next::method;
}

sub run ($self) {
    my $page = $self->index->current_page;
    $self->old_page($page);
    $self->set_lines( $self->render_text( $page->text ) );
    $self->next::method( $self->config->{keybindings} );
}

1;
