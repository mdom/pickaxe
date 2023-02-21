package App::pickaxe::AttachmentMenu;
use Mojo::Base 'App::pickaxe::UI::Index', -signatures;
use Mojo::File 'tempfile';
use Curses 'refresh';
use Mojo::URL;
use App::pickaxe::Getline 'getline';

has helpbar     => "q:Quit";
has statusbar   => "pickaxe: Attachments";
has attachments => sub { [] };
has 'api';

sub save_attachment ( $self, $key ) {
    my $attachment = $self->attachments->[ $self->current_line ];
    my $path = Mojo::URL->new($attachment->content_url )->path;
    my $file = getline("Save to file: ", { buffer => $attachment->filename });
    return if !$file;
    $self->api->get($path)->save_to( $file );
}

sub delete_attachment ( $self, $key ) {
    ...;
}

sub view_attachment ( $self, $key ) {
    return if !@{ $self->attachments };
    my $file = tempfile;
    my $path =
      Mojo::URL->new( $self->attachments->[ $self->current_line ]->content_url )
      ->path;
    $self->api->get($path)->save_to( $file->to_string );
    use IPC::Cmd;
    IPC::Cmd::run( command => [ 'xdg-open', $file ] );
    refresh;
}

sub run ( $self, $bindings ) {
    $self->set_lines( map { $_->filename } @{ $self->attachments } );
    $self->next::method($bindings);
}

1;
